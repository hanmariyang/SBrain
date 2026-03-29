import SwiftUI

struct AuthView: View {
    @EnvironmentObject var syncManager: SyncManager

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo area
            VStack(spacing: SB.Space.lg) {
                Image(systemName: "brain")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [SB.Colors.navy700, SB.Colors.gold600],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("SBrain")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [SB.Colors.navy700, SB.Colors.gold600],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Second Brain for iOS")
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy500)
            }
            .padding(.bottom, SB.Space.xxl)

            // Login form
            VStack(spacing: SB.Space.lg) {
                VStack(alignment: .leading, spacing: SB.Space.xs) {
                    Text("Username")
                        .font(SB.Font.caption())
                        .foregroundStyle(SB.Colors.navy500)

                    TextField("username", text: $username)
                        .textFieldStyle(.plain)
                        .font(SB.Font.bodyMd())
                        .foregroundStyle(SB.Colors.navy900)
                        .padding(SB.Space.md)
                        .background(
                            RoundedRectangle(cornerRadius: SB.Radius.sm)
                                .fill(SB.Colors.bgSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SB.Radius.sm)
                                .stroke(SB.Colors.navy100, lineWidth: 1)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: SB.Space.xs) {
                    Text("Password")
                        .font(SB.Font.caption())
                        .foregroundStyle(SB.Colors.navy500)

                    SecureField("password", text: $password)
                        .textFieldStyle(.plain)
                        .font(SB.Font.bodyMd())
                        .foregroundStyle(SB.Colors.navy900)
                        .padding(SB.Space.md)
                        .background(
                            RoundedRectangle(cornerRadius: SB.Radius.sm)
                                .fill(SB.Colors.bgSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SB.Radius.sm)
                                .stroke(SB.Colors.navy100, lineWidth: 1)
                        )
                }

                if let error = errorMessage {
                    HStack(spacing: SB.Space.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text(error)
                            .font(SB.Font.bodySm())
                    }
                    .foregroundStyle(SB.Colors.accentRed)
                }

                Button(action: { Task { await login() } }) {
                    HStack(spacing: SB.Space.sm) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text("Sign In")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SB.Space.md)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: SB.Radius.sm)
                            .fill(canSubmit ? SB.Colors.gold600 : SB.Colors.navy300)
                    )
                }
                .disabled(!canSubmit)
            }
            .padding(.horizontal, SB.Space.xxl)

            Spacer()

            // Footer
            Text("Railway Cloud API")
                .font(SB.Font.monoSm())
                .foregroundStyle(SB.Colors.navy300)
                .padding(.bottom, SB.Space.lg)
        }
        .background(SB.Colors.bgPrimary)
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        !isLoading
    }

    private func login() async {
        isLoading = true
        errorMessage = nil

        do {
            try await syncManager.login(username: username, password: password)
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
