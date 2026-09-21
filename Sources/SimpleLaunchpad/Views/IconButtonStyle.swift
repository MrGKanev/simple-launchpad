import SwiftUI

/// Shrinks and fades an icon briefly while pressed, mirroring the classic
/// Launchpad "pop" feedback on click. `ButtonStyle.Configuration.isPressed`
/// is supplied by SwiftUI itself, so this needs no `@State` of its own.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
