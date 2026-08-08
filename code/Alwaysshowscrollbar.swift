import SwiftUI
import AppKit

/// Finds the nearest enclosing NSScrollView and forces its scrollbar to
/// always be visible (classic, non-overlay style), rather than following
/// the system-wide "auto-hide" scrollbar preference. Scoped to just
/// whichever ScrollView this is placed inside — not an app-wide change.
///
/// SwiftUI's `showsIndicators` and `.scrollIndicators()` only *permit* a
/// scrollbar to be shown; actual visibility timing still follows macOS's
/// system-wide "Show scroll bars" setting on most Macs, which is why
/// those alone weren't enough here. This drops down to AppKit to
/// override that for one specific scroll view.
struct AlwaysShowsScrollbar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ view: NSView) {
        var current: NSView? = view.superview
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                scrollView.scrollerStyle = .legacy
                scrollView.autohidesScrollers = false
                scrollView.hasVerticalScroller = true
                return
            }
            current = candidate.superview
        }
    }
}
