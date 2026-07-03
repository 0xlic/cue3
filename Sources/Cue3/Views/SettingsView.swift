import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
struct SettingsRootView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }

            ShortcutSettingsView(settings: settings)
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            CueSettingsView(settings: settings)
                .tabItem {
                    Label("Cue", systemImage: "text.quote")
                }

            AboutSettingsView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 360)
    }
}

@MainActor
private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "界面") {
                VStack(alignment: .leading, spacing: 12) {
                    GeneralSettingsRow(title: "显示") {
                        Picker("显示", selection: $settings.appearanceMode) {
                            ForEach(AppSettings.AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    Divider()

                    GeneralSettingsRow(title: "清理") {
                        Text(AppSettings.defaultCleanupDescription)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection(title: "启动") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("开机自启动", isOn: $settings.launchAtLoginEnabled)
                        .toggleStyle(.switch)

                    Divider()

                    Toggle("启动后打开主窗口", isOn: $settings.openMainWindowOnLaunch)
                        .toggleStyle(.switch)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct ShortcutSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "快捷键") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(AppSettings.MenuAction.allCases) { action in
                        ShortcutSettingsRow(
                            title: action.title,
                            shortcut: binding(for: action),
                            defaultShortcut: action.defaultShortcut
                        ) {
                            settings.resetShortcut(for: action)
                        }
                    }

                    if let duplicateShortcutWarning = settings.duplicateShortcutWarning {
                        Text(duplicateShortcutWarning)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(for action: AppSettings.MenuAction) -> Binding<ShortcutConfiguration?> {
        Binding(
            get: { settings.shortcut(for: action) },
            set: { settings.setShortcut($0, for: action) }
        )
    }
}

@MainActor
private struct CueSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Cue 提示词") {
                VStack(alignment: .leading, spacing: 8) {
                    PromptTemplateEditor(text: $settings.cuePrompt)
                        .frame(height: 220)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        }

                    HStack(alignment: .center, spacing: 8) {
                        Text("支持")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        CuePlaceholderBadge()

                        Text("占位符，可自由组织静态内容和动态内容；留空时使用默认模板。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        Button("恢复默认") {
                            settings.resetCuePrompt()
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
    }
}

@MainActor
private struct GeneralSettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
private struct ShortcutSettingsRow: View {
    let title: String
    @Binding var shortcut: ShortcutConfiguration?
    let defaultShortcut: ShortcutConfiguration
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .frame(width: 44, alignment: .leading)

            ShortcutRecorderField(shortcut: $shortcut)
                .frame(maxWidth: .infinity)

            Button {
                reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("恢复默认")
            .disabled(shortcut == defaultShortcut)
        }
        .padding(.vertical, 3)
    }
}

@MainActor
private struct ShortcutRecorderField: View {
    @Binding var shortcut: ShortcutConfiguration?
    @State private var isRecording = false

    var body: some View {
        ZStack(alignment: .trailing) {
            ShortcutRecorderRepresentable(
                shortcut: $shortcut,
                isRecording: $isRecording
            )
            .frame(height: 32)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }

            if shortcut != nil {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var borderColor: Color {
        isRecording ? .accentColor : Color.secondary.opacity(0.16)
    }
}

@MainActor
private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    @Binding var shortcut: ShortcutConfiguration?
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> ShortcutRecorderTextField {
        let textField = ShortcutRecorderTextField()
        textField.coordinator = context.coordinator
        textField.alignment = .center
        textField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.textColor = .labelColor
        textField.focusRingType = .none
        textField.isBordered = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.isSelectable = false
        return textField
    }

    func updateNSView(_ nsView: ShortcutRecorderTextField, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.stringValue = displayText
        nsView.textColor = isRecording ? .controlAccentColor : .labelColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut, isRecording: $isRecording)
    }

    private var displayText: String {
        if isRecording {
            return "按下快捷键"
        }
        return shortcut?.displayString ?? "点按后录制快捷键"
    }

    @MainActor
    final class Coordinator {
        @Binding private var shortcut: ShortcutConfiguration?
        @Binding private var isRecording: Bool

        init(
            shortcut: Binding<ShortcutConfiguration?>,
            isRecording: Binding<Bool>
        ) {
            _shortcut = shortcut
            _isRecording = isRecording
        }

        func beginRecording() {
            isRecording = true
        }

        func endRecording() {
            isRecording = false
        }

        func handle(event: NSEvent) {
            switch Int(event.keyCode) {
            case kVK_Delete, kVK_ForwardDelete:
                shortcut = nil
                endRecording()
            case kVK_Escape:
                endRecording()
            default:
                guard let shortcut = ShortcutConfiguration(event: event) else {
                    NSSound.beep()
                    return
                }
                self.shortcut = shortcut
                endRecording()
            }
        }
    }
}

@MainActor
private final class ShortcutRecorderTextField: NSTextField {
    weak var coordinator: ShortcutRecorderRepresentable.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        coordinator?.beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        coordinator?.handle(event: event)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        coordinator?.endRecording()
        return super.resignFirstResponder()
    }
}

@MainActor
private struct CuePlaceholderBadge: View {
    var body: some View {
        Text(AppSettings.cuePlaceholder)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
            }
    }
}

@MainActor
private struct PromptTemplateEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        context.coordinator.applyHighlight(to: textView, text: text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            context.coordinator.applyHighlight(to: textView, text: text)
        } else {
            context.coordinator.refreshHighlight(in: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private var isApplyingHighlight = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            guard !isApplyingHighlight else {
                return
            }
            text = textView.string
            refreshHighlight(in: textView)
        }

        func refreshHighlight(in textView: NSTextView) {
            applyHighlight(to: textView, text: textView.string)
        }

        func applyHighlight(to textView: NSTextView, text: String) {
            guard let textStorage = textView.textStorage else {
                return
            }

            isApplyingHighlight = true
            let selectedRanges = textView.selectedRanges
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
            let highlightedAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12)
            ]

            let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
            let fullRange = NSRange(location: 0, length: attributed.length)
            let pattern = NSRegularExpression.escapedPattern(for: AppSettings.cuePlaceholder)
            if let regex = try? NSRegularExpression(pattern: pattern) {
                for match in regex.matches(in: text, range: fullRange) {
                    attributed.addAttributes(highlightedAttributes, range: match.range)
                }
            }

            textStorage.setAttributedString(attributed)
            textView.selectedRanges = selectedRanges
            textView.typingAttributes = baseAttributes
            isApplyingHighlight = false
        }
    }
}

@MainActor
private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            AppIconImage(size: 96)

            Text("Cue3")
                .font(.title2)
                .fontWeight(.semibold)

            Text("版本号 \(appVersion)")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .padding(24)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知版本"
    }
}

@MainActor
private struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "app.fill")
                        .font(.system(size: size * 0.34, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
        }
    }

    private var appIcon: NSImage? {
        NSApp.applicationIconImage
    }
}
