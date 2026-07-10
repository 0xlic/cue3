import AppKit
import Foundation
import SwiftUI

@MainActor
struct CueDetailView: View {
    @Bindable var store: CueStore
    @Bindable var panelState: PanelState
    let cue: CueRecord
    @State private var deletedItem: CueStore.DeletedItemSnapshot?
    @State private var editingAnnotationItemID: UUID?
    @State private var annotationDraft = ""
    @State private var annotationFocused = false
    private var orderedItems: [CueItemRecord] {
        store.orderedItems(for: cue)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if orderedItems.isEmpty {
                        emptyCueState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(orderedItems, id: \.id) { item in
                                CueItemRow(
                                    item: item,
                                    isEditingAnnotation: editingAnnotationItemID == item.id,
                                    annotationDraft: $annotationDraft,
                                    annotationFocused: annotationFocusBinding(for: item)
                                ) {
                                    startEditingAnnotation(for: item)
                                } onDelete: {
                                    deleteItem(item)
                                }
                                .id(item.id)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .animation(.easeInOut(duration: 0.22), value: orderedItems.map(\.id))
                    }
                }
                .scrollIndicators(.hidden)
                .background(ScrollIndicatorDisabler())
                .onAppear {
                    scrollToBottom(proxy)
                }
                .onChange(of: store.itemCount(for: cue)) {
                    scrollToBottom(proxy)
                }
                .onChange(of: editingAnnotationItemID) {
                    scrollToEditingAnnotation(proxy)
                }
                .onChange(of: annotationFocused) {
                    guard annotationFocused else { return }
                    scrollToEditingAnnotation(proxy)
                }
            }

            if deletedItem != nil {
                undoBanner
                SoftSeparator()
            }

            SoftSeparator()
            outputBar
        }
        .background(ClickAwayFocusResigner())
    }

    private var emptyCueState: some View {
        ContentUnavailableView {
            Label("等待引用", systemImage: "text.cursor")
        } description: {
            Text("选中文本后使用菜单或快捷键捕获到当前 Cue。")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(24)
    }

    private var undoBanner: some View {
        HStack {
            Text("已删除段落")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("撤销") {
                guard let deletedItem else { return }
                perform {
                    try store.restoreItem(deletedItem)
                    self.deletedItem = nil
                }
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var outputBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                OutputActionButton(
                    title: "设置",
                    systemImage: "gearshape",
                    action: {
                        openSettings()
                    }
                )

                OutputActionButton(
                    title: "新建",
                    systemImage: "plus",
                    action: {
                        startNewCue()
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(orderedItems.count) 段")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 64)

            HStack(spacing: 8) {
                OutputActionButton(
                    title: "捕获",
                    systemImage: "text.viewfinder",
                    action: {
                        captureSelection()
                    }
                )

                OutputActionButton(
                    title: "Cue",
                    systemImage: "sparkles",
                    isProminent: true,
                    isDisabled: orderedItems.isEmpty,
                    action: {
                        pasteCueOutput()
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func startNewCue() {
        perform {
            let cue = try store.startNewCue()
            panelState.selectedCueID = cue.id
        }
    }

    private func openSettings() {
        panelState.openSettings?()
    }

    private func captureSelection() {
        panelState.captureSelection?()
    }

    private func pasteCueOutput() {
        panelState.pasteCue?(cue.id)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                if let lastID = orderedItems.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private func scrollToEditingAnnotation(_ proxy: ScrollViewProxy) {
        guard let itemID = editingAnnotationItemID else { return }
        for delay in [0.0, 0.12] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(itemID, anchor: .bottom)
                }
            }
        }
    }

    private func annotationFocusBinding(for item: CueItemRecord) -> Binding<Bool> {
        Binding {
            editingAnnotationItemID == item.id && annotationFocused
        } set: { focused in
            guard editingAnnotationItemID == item.id else { return }
            annotationFocused = focused
            if !focused {
                saveEditingAnnotation()
            }
        }
    }

    private func startEditingAnnotation(for item: CueItemRecord) {
        if editingAnnotationItemID == item.id {
            annotationFocused = true
            return
        }

        saveEditingAnnotation()
        annotationDraft = item.annotationText ?? ""
        editingAnnotationItemID = item.id
        annotationFocused = true
    }

    private func saveEditingAnnotation() {
        guard let itemID = editingAnnotationItemID else { return }
        let draft = annotationDraft
        let didSave = perform {
            try store.updateAnnotation(
                itemID: itemID,
                annotationText: draft
            )
        }
        guard didSave else {
            DispatchQueue.main.async {
                annotationFocused = true
            }
            return
        }
        editingAnnotationItemID = nil
        annotationFocused = false
    }

    private func deleteItem(_ item: CueItemRecord) {
        do {
            if editingAnnotationItemID == item.id {
                editingAnnotationItemID = nil
                annotationDraft = ""
                annotationFocused = false
            }
            let snapshot = try withAnimation(.easeInOut(duration: 0.22)) {
                try store.deleteItem(itemID: item.id)
            }
            withAnimation(.easeOut(duration: 0.16)) {
                deletedItem = snapshot
                scheduleUndoDismissal(for: snapshot)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func scheduleUndoDismissal(for snapshot: CueStore.DeletedItemSnapshot) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if deletedItem == snapshot {
                deletedItem = nil
            }
        }
    }

    @discardableResult
    private func perform(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return true
        } catch {
            store.errorMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
private struct CueItemRow: View {
    let item: CueItemRecord
    let isEditingAnnotation: Bool
    @Binding var annotationDraft: String
    @Binding var annotationFocused: Bool
    let onStartEditing: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    init(
        item: CueItemRecord,
        isEditingAnnotation: Bool,
        annotationDraft: Binding<String>,
        annotationFocused: Binding<Bool>,
        onStartEditing: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isEditingAnnotation = isEditingAnnotation
        _annotationDraft = annotationDraft
        _annotationFocused = annotationFocused
        self.onStartEditing = onStartEditing
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                quoteButton
                    .layoutPriority(1)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 22, height: 26)
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 26)
                .opacity(isHovering ? 1 : 0)
                .help("删除段落")
            }

            if isEditingAnnotation {
                HStack(alignment: .top, spacing: 0) {
                    Text("批注：")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    PlainAnnotationTextView(
                        placeholder: "",
                        text: $annotationDraft,
                        isFocused: $annotationFocused
                    )
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
                .padding(.horizontal, 8)
            } else if let annotationText = item.annotationText, !annotationText.isEmpty {
                Text("批注：\(annotationText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 4)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .animation(.easeOut(duration: 0.16), value: isEditingAnnotation)
    }

    private var quoteButton: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(CueViewsChrome.swiftUITint.opacity(isHovering ? 0.62 : 0.36))
                .frame(width: 3)
                .padding(.vertical, 4)

            Text(item.quoteText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help("添加或编辑批注")
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.16)) {
                onStartEditing()
            }
        }
    }
}

enum CueViewsChrome {
    static let tintStrong = NSColor(
        calibratedRed: 0.36,
        green: 0.48,
        blue: 0.58,
        alpha: 1
    )
    static let swiftUITint = Color(red: 0.42, green: 0.54, blue: 0.64)
}

@MainActor
private struct PlainAnnotationTextView: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .callout)
        textView.textColor = .secondaryLabelColor
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        guard isFocused else {
            context.coordinator.didApplyProgrammaticFocus = false
            return
        }
        guard !context.coordinator.didApplyProgrammaticFocus else { return }
        context.coordinator.didApplyProgrammaticFocus = true
        DispatchQueue.main.async {
            guard let window = textView.window else {
                context.coordinator.didApplyProgrammaticFocus = false
                return
            }
            window.makeFirstResponder(textView)
            let endLocation = (textView.string as NSString).length
            textView.selectedRange = NSRange(location: endLocation, length: 0)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        var didApplyProgrammaticFocus = false

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            didApplyProgrammaticFocus = false
            isFocused = false
        }
    }
}

@MainActor
private struct ClickAwayFocusResigner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = false
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(to: view)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private weak var view: NSView?
        private var monitor: Any?

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func attach(to view: NSView) {
            guard self.view !== view else { return }
            self.view = view
            installMonitorIfNeeded()
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                self?.resignTextFieldFocusIfNeeded(for: event)
                return event
            }
        }

        private func resignTextFieldFocusIfNeeded(for event: NSEvent) {
            guard let window = view?.window, event.window === window else { return }
            guard let hitView = window.contentView?.hitTest(event.locationInWindow) else { return }
            guard !hitView.isInsideTextField else { return }
            window.makeFirstResponder(nil)
        }
    }
}

private extension NSView {
    var isInsideTextField: Bool {
        if self is NSTextField || self is NSTextView {
            return true
        }
        return superview?.isInsideTextField ?? false
    }

}
