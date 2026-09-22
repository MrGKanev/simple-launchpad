import SwiftUI
import AppKit

// A native NSSearchField instead of SwiftUI's `TextField`: it routes editing
// (backspace/delete, select-all, etc.) through AppKit's normal field-editor
// responder chain, which proved more reliable than SwiftUI's binding inside
// this borderless overlay window, and it comes with a working built-in
// clear ("x") button for free.
struct SearchField: NSViewRepresentable {
    @Binding var query: String
    // Scales with `IconGridMetrics.scale` (see LaunchpadView) so the field's
    // text tracks the rest of the overlay's screen-relative sizing instead
    // of staying a fixed point size on every display.
    var fontSize: CGFloat = 20
    var palette: LaunchpadPalette = LaunchpadPalette(isDark: true)

    func makeCoordinator() -> Coordinator {
        Coordinator(query: $query)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.font = .systemFont(ofSize: fontSize)
        field.focusRingType = .none
        field.delegate = context.coordinator
        // No native bezel/background — `LaunchpadView` draws a `Capsule`
        // behind this instead, so the field reads as the exact same pill
        // shape as the category bar right below it rather than AppKit's own
        // fixed-radius rounded-rect search field look.
        field.isBezeled = false
        field.drawsBackground = false
        applyPalette(to: field)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != query {
            nsView.stringValue = query
        }
        if nsView.font?.pointSize != fontSize {
            nsView.font = .systemFont(ofSize: fontSize)
        }
        applyPalette(to: nsView)
    }

    // Text/placeholder color no longer comes for free from a native bezel
    // (see `isBezeled`/`drawsBackground` above), so it's driven explicitly
    // off the same palette every other piece of overlay chrome uses —
    // otherwise dark text would vanish against a dark "Light" pill fill,
    // and vice versa.
    private func applyPalette(to field: NSSearchField) {
        field.textColor = NSColor(palette.text)
        field.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: NSColor(palette.secondaryText)]
        )
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let query: Binding<String>

        init(query: Binding<String>) {
            self.query = query
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            query.wrappedValue = field.stringValue
        }
    }
}
