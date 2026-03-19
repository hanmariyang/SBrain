import SwiftUI

// MARK: - Card Container

struct SBCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(SB.Space.md)
            .background(
                RoundedRectangle(cornerRadius: SB.Radius.md)
                    .fill(SB.Colors.bgElevated)
                    .shadow(color: Color(hex: "1B2A4A").opacity(0.08), radius: 3, x: 0, y: 1)
            )
    }
}

// MARK: - Badge

struct SBBadge: View {
    let text: String
    var color: Color = SB.Colors.gold600

    var body: some View {
        Text(text)
            .font(SB.Font.caption())
            .foregroundStyle(color)
            .padding(.horizontal, SB.Space.sm)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Divider

struct SBDivider: View {
    var body: some View {
        Rectangle()
            .fill(SB.Colors.navy100)
            .frame(height: 1)
    }
}

// MARK: - Search Field

struct SBSearchField: View {
    @Binding var text: String
    var placeholder: String = "검색..."
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: SB.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(SB.Colors.navy500)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(SB.Font.bodyMd())
                .foregroundStyle(SB.Colors.navy900)
                .onSubmit { onSubmit?() }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SB.Colors.navy300)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SB.Space.md)
        .padding(.vertical, SB.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: SB.Radius.full)
                .fill(SB.Colors.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: SB.Radius.full)
                        .stroke(SB.Colors.navy100, lineWidth: 1)
                )
        )
    }
}

// MARK: - Section Header

struct SBSectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(SB.Font.caption())
                .foregroundStyle(SB.Colors.navy500)
                .textCase(.uppercase)

            Spacer()

            if let trailing { trailing }
        }
        .padding(.horizontal, SB.Space.lg)
        .padding(.vertical, SB.Space.xs)
    }
}
