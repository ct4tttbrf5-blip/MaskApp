import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    static let maskBackground = Color(hex: 0x0F1226)
    static let maskCard = Color(hex: 0x1A2040)
    static let maskCardRaised = Color(hex: 0x232B52)
    static let maskBorder = Color(hex: 0x39446E)
    static let maskAccent = Color(hex: 0x5DE0C8)
    static let maskAccentBlue = Color(hex: 0x7AA8FF)
    static let maskWarning = Color(hex: 0xF5B971)
    static let maskDanger = Color(hex: 0xF28B82)
    static let maskText = Color(hex: 0xEEF4FF)
    static let maskTextSecondary = Color(hex: 0x99A4C6)
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.maskCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.maskBorder.opacity(0.6), lineWidth: 0.5)
            )
    }
}

extension View {
    func maskCard(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.maskTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .maskAccent
    var disabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(disabled ? .maskTextSecondary : .maskBackground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(disabled ? Color.maskCardRaised : tint)
            )
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
    }
}
