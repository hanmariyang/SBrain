import SwiftUI

// MARK: - Button Styles

struct SBPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SB.Font.bodyMd())
            .foregroundStyle(.white)
            .padding(.horizontal, SB.Space.lg)
            .padding(.vertical, SB.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(configuration.isPressed ? SB.Colors.navy700 : SB.Colors.navy900)
            )
    }
}

struct SBSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SB.Font.bodyMd())
            .foregroundStyle(SB.Colors.navy900)
            .padding(.horizontal, SB.Space.lg)
            .padding(.vertical, SB.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(configuration.isPressed ? SB.Colors.bgTertiary : SB.Colors.bgSecondary)
            )
    }
}

struct SBGoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SB.Font.bodyMd())
            .foregroundStyle(.white)
            .padding(.horizontal, SB.Space.lg)
            .padding(.vertical, SB.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(configuration.isPressed ? SB.Colors.gold400 : SB.Colors.gold600)
            )
    }
}

struct SBGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SB.Font.bodyMd())
            .foregroundStyle(SB.Colors.navy700)
            .padding(.horizontal, SB.Space.md)
            .padding(.vertical, SB.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.sm)
                    .fill(configuration.isPressed ? SB.Colors.bgTertiary : Color.clear)
            )
    }
}

// MARK: - Icon Button (for sidebar, toolbar)

struct SBIconButton: View {
    let icon: String
    let isActive: Bool
    var size: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.6))
                .frame(width: size + 8, height: size + 8)
                .foregroundStyle(isActive ? SB.Colors.gold600 : SB.Colors.navy500)
                .background(
                    RoundedRectangle(cornerRadius: SB.Radius.sm)
                        .fill(isActive ? SB.Colors.gold100 : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
