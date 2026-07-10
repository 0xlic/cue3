import AppKit
import SwiftUI

@MainActor
struct OutputActionButton: NSViewRepresentable {
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
final class NonActivatingOutputButton: NSView {
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
        let shouldPerformAction = isPressed
            && !isDisabled
            && bounds.contains(convert(event.locationInWindow, from: nil))
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
