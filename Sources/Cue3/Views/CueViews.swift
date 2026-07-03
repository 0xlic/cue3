import AppKit
import CoreGraphics
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
        perform {
            let text = try store.cueOutputText(cueID: cue.id)
            paste(text)
        }
    }

    private func paste(_ text: String) {
        guard let application = panelState.resolvedTargetApplication else {
            store.errorMessage = "找不到可粘贴的目标应用。请先切回需要输入的应用后再打开 Cue。"
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        if isFrontmost(application) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                postCommandV()
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let activated = application.activate(options: [])
            guard activated else {
                store.errorMessage = "无法切回目标应用，未执行粘贴。"
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                postCommandV()
            }
        }
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
        perform {
            try store.updateAnnotation(
                itemID: itemID,
                annotationText: draft
            )
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

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private struct OutputActionButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    var isProminent = false
    var isDisabled = false
    let action: () -> Void

    func makeNSView(context: Context) -> NonActivatingOutputButton {
        NonActivatingOutputButton(
            title: title,
            systemImage: systemImage,
            isProminent: isProminent,
            isDisabled: isDisabled,
            action: action
        )
    }

    func updateNSView(_ view: NonActivatingOutputButton, context: Context) {
        view.title = title
        view.systemImage = systemImage
        view.isProminent = isProminent
        view.isDisabled = isDisabled
        view.action = action
    }
}

@MainActor
private final class NonActivatingOutputButton: NSView {
    var title: String {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }
    var systemImage: String {
        didSet {
            imageView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
            invalidateIntrinsicContentSize()
        }
    }
    var isProminent: Bool {
        didSet { updateAppearance() }
    }
    var isDisabled: Bool {
        didSet { updateAppearance() }
    }
    var action: () -> Void

    private let imageView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { updateAppearance() }
    }
    private var isPressed = false {
        didSet { updateAppearance() }
    }

    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    init(
        title: String,
        systemImage: String,
        isProminent: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isProminent = isProminent
        self.isDisabled = isDisabled
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0

        imageView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        imageView.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 15),
            imageView.heightAnchor.constraint(equalToConstant: 15),
            heightAnchor.constraint(equalToConstant: 30)
        ])

        setAccessibilityRole(.button)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        guard !isDisabled else { return }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let shouldPerformAction = isPressed && !isDisabled && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if shouldPerformAction {
            action()
        }
    }

    private func updateAppearance() {
        alphaValue = isDisabled ? 0.45 : 1
        imageView.contentTintColor = foregroundColor
        layer?.backgroundColor = backgroundColor.cgColor
        setAccessibilityLabel(title)
        setAccessibilityEnabled(!isDisabled)
    }

    private var foregroundColor: NSColor {
        if isProminent {
            return CueViewsChrome.tintStrong
        }
        return isHovering ? CueViewsChrome.tintStrong : .secondaryLabelColor
    }

    private var backgroundColor: NSColor {
        if isPressed {
            return isProminent
                ? CueViewsChrome.tintStrong.withAlphaComponent(0.14)
                : NSColor.labelColor.withAlphaComponent(0.08)
        }
        if isProminent {
            return CueViewsChrome.tintStrong.withAlphaComponent(isHovering ? 0.10 : 0.00)
        }
        return isHovering ? NSColor.labelColor.withAlphaComponent(0.06) : .clear
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
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("批注：")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    PlainAnnotationTextField(
                        placeholder: "",
                        text: $annotationDraft,
                        isFocused: $annotationFocused
                    )
                    .font(.callout)
                    .frame(maxWidth: .infinity)
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

private enum CueViewsChrome {
    static let tintStrong = NSColor(
        calibratedRed: 0.36,
        green: 0.48,
        blue: 0.58,
        alpha: 1
    )
    static let swiftUITint = Color(red: 0.42, green: 0.54, blue: 0.64)
}

@MainActor
struct ScrollIndicatorDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.configure(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.configure(from: view)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        func configure(from view: NSView) {
            for delay in [0.0, 0.05, 0.2, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.disableScrollIndicators(near: view)
                }
            }
        }

        private func disableScrollIndicators(near view: NSView) {
            let candidates = view.window?.contentView?.allScrollViews ?? view.allScrollViews
            candidates.forEach(apply)
        }

        private func apply(to scrollView: NSScrollView) {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.isHidden = true
            scrollView.horizontalScroller?.isHidden = true
            scrollView.scrollerStyle = .overlay
            scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
    }
}

@MainActor
private struct PlainAnnotationTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.font = .preferredFont(forTextStyle: .callout)
        textField.textColor = .secondaryLabelColor
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 4
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.placeholderString = placeholder
        guard isFocused else {
            context.coordinator.didApplyProgrammaticFocus = false
            return
        }
        guard !context.coordinator.didApplyProgrammaticFocus else { return }
        context.coordinator.didApplyProgrammaticFocus = true
        DispatchQueue.main.async {
            guard let window = textField.window else {
                context.coordinator.didApplyProgrammaticFocus = false
                return
            }
            window.makeFirstResponder(textField)
            if let editor = textField.currentEditor() {
                let endLocation = (textField.stringValue as NSString).length
                editor.selectedRange = NSRange(location: endLocation, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        var didApplyProgrammaticFocus = false

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
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

    var allScrollViews: [NSScrollView] {
        var result = [NSScrollView]()
        if let scrollView = self as? NSScrollView {
            result.append(scrollView)
        }
        for subview in subviews {
            result.append(contentsOf: subview.allScrollViews)
        }
        return result
    }
}

private func postCommandV() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    keyDown?.flags = .maskCommand
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

private func isFrontmost(_ application: NSRunningApplication) -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
}
