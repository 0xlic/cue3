import AppKit
import SwiftUI

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
        private weak var sourceView: NSView?
        private var didConfigure = false
        private var isScheduling = false
        private var generation = 0

        func configure(from view: NSView) {
            if sourceView !== view {
                sourceView = view
                didConfigure = false
                isScheduling = false
                generation += 1
            }
            guard !didConfigure, !isScheduling else { return }

            isScheduling = true
            let currentGeneration = generation
            let delays = [0.0, 0.05, 0.2, 0.6]
            for (index, delay) in delays.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak view] in
                    guard let self, generation == currentGeneration else { return }
                    if let view, !didConfigure {
                        didConfigure = disableNearestScrollIndicator(to: view)
                    }
                    if index == delays.count - 1 {
                        isScheduling = false
                    }
                }
            }
        }

        private func disableNearestScrollIndicator(to view: NSView) -> Bool {
            if let ancestor = nearestScrollViewAncestor(of: view) {
                apply(to: ancestor)
                return true
            }

            guard let contentView = view.window?.contentView else { return false }
            let referenceRect = view.convert(view.bounds, to: nil)
            let candidates = scrollViews(in: contentView)
            guard let bestMatch = candidates.max(by: { lhs, rhs in
                overlapScore(lhs, with: referenceRect) < overlapScore(rhs, with: referenceRect)
            }), overlapScore(bestMatch, with: referenceRect) > 0 else {
                return false
            }

            apply(to: bestMatch)
            return true
        }

        private func nearestScrollViewAncestor(of view: NSView) -> NSScrollView? {
            var candidate: NSView? = view
            while let current = candidate {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                candidate = current.superview
            }
            return nil
        }

        private func scrollViews(in view: NSView) -> [NSScrollView] {
            var result: [NSScrollView] = []
            if let scrollView = view as? NSScrollView {
                result.append(scrollView)
            }
            for subview in view.subviews {
                result.append(contentsOf: scrollViews(in: subview))
            }
            return result
        }

        private func overlapScore(_ scrollView: NSScrollView, with referenceRect: NSRect) -> CGFloat {
            let scrollRect = scrollView.convert(scrollView.bounds, to: nil)
            let intersection = scrollRect.intersection(referenceRect)
            guard !intersection.isNull else { return 0 }
            return intersection.width * intersection.height
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
