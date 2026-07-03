import AppKit
import SwiftUI

@MainActor
struct MainPanelView: View {
    @Bindable var store: CueStore
    @Bindable var panelState: PanelState
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var isShowingCueList = false
    @FocusState private var titleFocused: Bool

    private var selectedCue: CueRecord? {
        if let selectedCueID = panelState.selectedCueID,
           let cue = store.cues.first(where: { $0.id == selectedCueID }) {
            return cue
        }
        return store.currentCue
    }

    var body: some View {
        panelBody
            .frame(minWidth: 300, minHeight: 500)
            .background(PanelSurface())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(PanelEdgeHighlight())
            .alert(
                "操作未完成",
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {
                    store.errorMessage = nil
                }
            } message: {
                Text(store.errorMessage ?? "未知错误")
            }
            .onChange(of: selectedCue?.id) {
                isEditingTitle = false
                titleFocused = false
            }
    }

    private var panelBody: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                detailPage
                    .frame(width: proxy.size.width, height: proxy.size.height)

                cueListPage
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width * 2, height: proxy.size.height, alignment: .leading)
            .offset(x: isShowingCueList ? -proxy.size.width : 0)
            .animation(.easeInOut(duration: 0.24), value: isShowingCueList)
            .clipped()
        }
    }

    private var detailPage: some View {
        VStack(spacing: 0) {
            detailHeader
            SoftSeparator()

            detailContent
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selectedCue {
            CueDetailView(
                store: store,
                panelState: panelState,
                cue: selectedCue
            )
        } else {
            emptyState
        }
    }

    private var cueListPage: some View {
        VStack(spacing: 0) {
            cueListHeader
            SoftSeparator()

            CueListView(store: store) { cue in
                selectCueFromList(cue)
            }
        }
    }

    private var detailHeader: some View {
        ZStack {
            HStack {
                HeaderIconButton(
                    icon: .cueList,
                    help: "历史记录",
                    action: showCueList
                )

                Spacer()

                HeaderIconButton(
                    icon: .system(panelState.isPinned ? "pin.fill" : "pin"),
                    isActive: panelState.isPinned,
                    help: panelState.isPinned ? "取消置顶" : "置顶"
                ) {
                    panelState.setPinned(!panelState.isPinned)
                }
            }

            VStack(spacing: 3) {
                if let selectedCue {
                    editableTitle(for: selectedCue)
                } else {
                    Text("Cue3")
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 210)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 14)
    }

    private var cueListHeader: some View {
        ZStack {
            HStack {
                HeaderIconButton(
                    icon: .cueList,
                    help: "返回详情",
                    action: hideCueList
                )

                Spacer()

                HeaderIconButton(
                    icon: .system(panelState.isPinned ? "pin.fill" : "pin"),
                    isActive: panelState.isPinned,
                    help: panelState.isPinned ? "取消置顶" : "置顶"
                ) {
                    panelState.setPinned(!panelState.isPinned)
                }
            }

            Text("\(store.cues.count) 个 Cue")
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: 210)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func editableTitle(for cue: CueRecord) -> some View {
        if isEditingTitle {
            TextField("未命名 Cue", text: $titleDraft)
                .font(.headline)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($titleFocused)
                .onSubmit {
                    saveTitle(for: cue)
                }
                .onChange(of: titleFocused) {
                    if !titleFocused {
                        saveTitle(for: cue)
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        titleFocused = true
                    }
                }
        } else {
            Text(store.displayTitle(for: cue))
                .font(.headline)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .contentShape(Rectangle())
                .onTapGesture {
                    startEditingTitle(for: cue)
                }
                .help("编辑标题")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有 Cue", systemImage: "quote.bubble")
        } description: {
            Text("新建上下文后，选中文本并捕获到当前 Cue。")
        } actions: {
            Button("新建上下文") {
                startNewCue()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func startNewCue() {
        perform {
            let cue = try store.startNewCue()
            panelState.selectedCueID = cue.id
        }
        isEditingTitle = false
        titleFocused = false
    }

    private func showCueList() {
        isEditingTitle = false
        titleFocused = false
        withAnimation(.easeInOut(duration: 0.24)) {
            isShowingCueList = true
        }
    }

    private func hideCueList() {
        withAnimation(.easeInOut(duration: 0.24)) {
            isShowingCueList = false
        }
    }

    private func selectCueFromList(_ cue: CueRecord) {
        perform {
            try store.restoreCurrent(cueID: cue.id)
            panelState.selectedCueID = cue.id
        }
        isEditingTitle = false
        titleFocused = false
        hideCueList()
    }

    private func startEditingTitle(for cue: CueRecord) {
        titleDraft = store.titleDraft(for: cue)
        isEditingTitle = true
        DispatchQueue.main.async {
            titleFocused = true
        }
    }

    private func saveTitle(for cue: CueRecord) {
        guard isEditingTitle else { return }
        perform {
            try store.updateTitle(cueID: cue.id, titleText: titleDraft)
        }
        isEditingTitle = false
        titleFocused = false
    }
}

@MainActor
private struct CueListView: View {
    let store: CueStore
    let onSelectCue: (CueRecord) -> Void

    private var recentCues: [CueRecord] {
        store.recentCues
    }

    private var historyCues: [CueRecord] {
        let recentIDs = Set(recentCues.map(\.id))
        return store.historyCues.filter { !recentIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            if store.cues.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(recentCues, id: \.id) { cue in
                        CueBlockView(
                            title: store.displayTitle(for: cue),
                            preview: previewText(for: cue),
                            itemCount: store.itemCount(for: cue),
                            updatedAt: cue.updatedAt,
                            isCurrent: cue.id == store.currentCueID,
                            isEmphasized: true
                        ) {
                            onSelectCue(cue)
                        }
                        .id("recent-\(cue.id.uuidString)")
                    }

                    if !historyCues.isEmpty {
                        Text("历史")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.horizontal, 2)

                        ForEach(historyCues, id: \.id) { cue in
                            CueBlockView(
                                title: store.displayTitle(for: cue),
                                preview: previewText(for: cue),
                                itemCount: store.itemCount(for: cue),
                                updatedAt: cue.updatedAt,
                                isCurrent: cue.id == store.currentCueID,
                                isEmphasized: false
                            ) {
                                onSelectCue(cue)
                            }
                            .id("history-\(cue.id.uuidString)")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .scrollIndicators(.hidden)
        .background(ScrollIndicatorDisabler())
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有 Cue", systemImage: "quote.bubble")
        } description: {
            Text("捕获文本后会出现在这里。")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(24)
    }

    private func previewText(for cue: CueRecord) -> String {
        let items = store.orderedItems(for: cue)
        guard let firstItem = items.first else {
            return "暂无引用内容"
        }

        if let annotationText = firstItem.annotationText, !annotationText.isEmpty {
            return "\(firstItem.quoteText)\n批注：\(annotationText)"
        }

        return firstItem.quoteText
    }
}

private struct CueBlockView: View {
    let title: String
    let preview: String
    let itemCount: Int
    let updatedAt: Date
    let isCurrent: Bool
    let isEmphasized: Bool
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false

    private var isActiveAppearance: Bool {
        isCurrent || isEmphasized
    }

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(itemCount) 段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                Text(preview)
                    .font(.caption)
                    .foregroundStyle(previewColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(updatedAtText)
                    .font(.caption2)
                    .foregroundStyle(updatedAtColor)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .topLeading)
            .background(cardBackground)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(isPressed ? 0.992 : 1)
        }
        .buttonStyle(.plain)
        .opacity(isActiveAppearance ? 1 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeOut(duration: 0.08)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isPressed = false
                    }
                }
        )
        .help("打开 Cue")
    }

    private var titleColor: Color {
        isActiveAppearance ? .primary : .secondary
    }

    private var previewColor: Color {
        isActiveAppearance ? .secondary : .secondary.opacity(0.76)
    }

    private var updatedAtColor: Color {
        isActiveAppearance ? .secondary.opacity(0.92) : .secondary.opacity(0.64)
    }

    private var accentColor: Color {
        if isCurrent {
            return MainPanelChrome.tintStrong
        }
        return isActiveAppearance ? MainPanelChrome.tint.opacity(0.42) : Color.secondary.opacity(0.22)
    }

    private var cardBackground: Color {
        if isPressed {
            return MainPanelChrome.cardFill.opacity(isActiveAppearance ? 0.95 : 0.90)
        }
        if isHovering {
            return MainPanelChrome.cardFill.opacity(isActiveAppearance ? 0.92 : 0.88)
        }
        return MainPanelChrome.cardFill.opacity(isActiveAppearance ? 0.88 : 0.82)
    }

    private var borderColor: Color {
        if isHovering {
            return Color.black.opacity(isActiveAppearance ? 0.09 : 0.06)
        }
        return Color.black.opacity(isActiveAppearance ? 0.06 : 0.035)
    }

    private var updatedAtText: String {
        if Calendar.current.isDate(updatedAt, inSameDayAs: Date()) {
            return Self.sameDayUpdatedAtFormatter.string(from: updatedAt)
        }
        return Self.crossDayUpdatedAtFormatter.string(from: updatedAt)
    }

    private static let sameDayUpdatedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let crossDayUpdatedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private enum HeaderIconKind {
    case cueList
    case system(String)
}

private struct HeaderIconButton: View {
    let icon: HeaderIconKind
    var isActive = false
    let help: String
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            iconView
                .foregroundStyle((isActive || isHovering) ? MainPanelChrome.tintStrong : Color.secondary)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(buttonBackground)
                }
                .scaleEffect(isPressed ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeOut(duration: 0.08)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isPressed = false
                    }
                }
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .cueList:
            CueListIcon()
        case .system(let systemName):
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var buttonBackground: Color {
        if isActive && isHovering {
            return MainPanelChrome.tint.opacity(0.10)
        }
        if isActive {
            return Color.clear
        }
        if isHovering {
            return MainPanelChrome.cardFill.opacity(0.92)
        }
        return Color.clear
    }
}

private struct CueListIcon: View {
    private let widths: [CGFloat] = [15, 10, 13]

    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                Capsule()
                    .frame(width: width, height: 1.8)
            }
        }
        .frame(width: 16, height: 14, alignment: .leading)
    }
}

struct SoftSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

private struct PanelSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(MainPanelChrome.panelFill.opacity(0.93))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.18), location: 0.0),
                                .init(color: Color.white.opacity(0.10), location: 0.34),
                                .init(color: Color.white.opacity(0.04), location: 0.70),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: MainPanelChrome.tint.opacity(0.035), location: 0.0),
                                .init(color: Color.white.opacity(0.02), location: 0.48),
                                .init(color: Color.black.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct PanelEdgeHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.72), location: 0.0),
                        .init(color: Color.white.opacity(0.36), location: 0.28),
                        .init(color: Color.white.opacity(0.10), location: 0.58),
                        .init(color: Color.black.opacity(0.12), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.4
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.34))
                    .frame(height: 1)
                    .padding(.horizontal, 34)
                    .padding(.top, 1)
            }
            .allowsHitTesting(false)
    }
}

private enum MainPanelChrome {
    static let tint = Color(red: 0.42, green: 0.54, blue: 0.64)
    static let tintStrong = Color(red: 0.36, green: 0.48, blue: 0.58)
    static let panelFill = Color(nsColor: .windowBackgroundColor)
    static let cardFill = Color(nsColor: .controlBackgroundColor)
}
