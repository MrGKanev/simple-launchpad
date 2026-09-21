import SwiftUI

struct SearchField: View {
    @Binding var query: String

    var body: some View {
        TextField("", text: $query, prompt: Text("Search").foregroundColor(.white.opacity(0.6)))
            .textFieldStyle(.plain)
            .font(.title3)
            .foregroundColor(.white)
            .padding(10)
            .frame(width: 280)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.15)))
    }
}
