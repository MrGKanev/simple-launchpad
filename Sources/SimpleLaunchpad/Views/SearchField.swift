import SwiftUI
import AppKit

// A native NSSearchField instead of SwiftUI's `TextField`: it routes editing
// (backspace/delete, select-all, etc.) through AppKit's normal field-editor
// responder chain, which proved more reliable than SwiftUI's binding inside
// this borderless overlay window, and it comes with a working built-in
// clear ("x") button for free.
struct SearchField: NSViewRepresentable {
    @Binding var query: String

    func makeCoordinator() -> Coordinator {
        Coordinator(query: $query)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search"
        field.font = .systemFont(ofSize: 20)
        field.focusRingType = .none
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != query {
            nsView.stringValue = query
        }
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
