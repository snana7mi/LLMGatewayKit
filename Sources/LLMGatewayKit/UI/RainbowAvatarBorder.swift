import SwiftUI

public struct RainbowAvatarBorder: ViewModifier {
    let isActive: Bool
    let size: CGFloat

    public func body(content: Content) -> some View {
        content.overlay {
            if isActive {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                            center: .center
                        ),
                        lineWidth: max(2, size * 0.055)
                    )
            }
        }
    }
}

public extension View {
    func rainbowAvatarBorder(isActive: Bool, size: CGFloat) -> some View {
        modifier(RainbowAvatarBorder(isActive: isActive, size: size))
    }
}
