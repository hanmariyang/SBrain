import SwiftUI

struct HandCursorOverlay: View {
    @EnvironmentObject var handTracking: HandTrackingManager

    var body: some View {
        GeometryReader { geo in
            if handTracking.isEnabled && handTracking.isTracking,
               let pos = handTracking.pointerPosition {
                let screenPos = CGPoint(
                    x: pos.x * geo.size.width,
                    y: pos.y * geo.size.height
                )

                // Cursor ring
                cursorView
                    .position(screenPos)

                // Gesture label (small, bottom-right of cursor)
                gestureLabel
                    .position(x: screenPos.x + 28, y: screenPos.y + 28)
            }

            // Hand tracking status indicator (top-right corner)
            if handTracking.isEnabled {
                statusIndicator
                    .position(x: geo.size.width - 40, y: 20)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Cursor

    @ViewBuilder
    private var cursorView: some View {
        let gesture = handTracking.gesture
        let conf = CGFloat(handTracking.confidence)

        ZStack {
            // Outer glow
            Circle()
                .fill(cursorColor(gesture).opacity(0.1 * Double(conf)))
                .frame(width: cursorSize(gesture) * 2, height: cursorSize(gesture) * 2)
                .blur(radius: 8)

            // Main ring
            Circle()
                .strokeBorder(cursorColor(gesture).opacity(0.6 * Double(conf)), lineWidth: 2)
                .frame(width: cursorSize(gesture), height: cursorSize(gesture))

            // Center dot
            Circle()
                .fill(cursorColor(gesture).opacity(0.8 * Double(conf)))
                .frame(width: 6, height: 6)

            // Dwell progress ring (pointing 2초 선택)
            if handTracking.dwellProgress > 0 && handTracking.dwellProgress < 1 {
                Circle()
                    .trim(from: 0, to: handTracking.dwellProgress)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: cursorSize(gesture) + 6, height: cursorSize(gesture) + 6)
                    .rotationEffect(.degrees(-90))
            }

            // Dwell confirmed flash
            if handTracking.dwellProgress >= 1 {
                Circle()
                    .fill(Color.yellow.opacity(0.4))
                    .frame(width: cursorSize(gesture) + 10, height: cursorSize(gesture) + 10)
            }

            // Pinch orbit indicator
            if gesture == .pinch {
                Circle()
                    .strokeBorder(Color.orange.opacity(0.5), lineWidth: 2)
                    .frame(width: cursorSize(gesture) + 8, height: cursorSize(gesture) + 8)
            }

            // Victory scroll arrows
            if gesture == .victory {
                VStack(spacing: 2) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 6, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                }
                .foregroundStyle(Color.green.opacity(0.7))
                .offset(x: cursorSize(gesture) / 2 + 8)
            }

            // FourFingers browse arrows
            if gesture == .fourFingers {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 6, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 6, weight: .bold))
                }
                .foregroundStyle(Color.mint.opacity(0.7))
                .offset(y: cursorSize(gesture) / 2 + 8)
            }
        }
        .animation(.easeOut(duration: 0.15), value: gesture)
        .animation(.easeOut(duration: 0.1), value: handTracking.pointerPosition ?? .zero)
    }

    private func cursorColor(_ gesture: HandGesture) -> Color {
        switch gesture {
        case .none: return .white
        case .pointing: return .cyan
        case .pinch: return .orange
        case .victory: return .green
        case .fourFingers: return .mint
        }
    }

    private func cursorSize(_ gesture: HandGesture) -> CGFloat {
        switch gesture {
        case .none: return 20
        case .pointing: return 24
        case .pinch: return 22
        case .victory: return 28
        case .fourFingers: return 30
        }
    }

    // MARK: - Gesture Label

    private var gestureLabel: some View {
        Group {
            if handTracking.gesture != .none {
                Text(gestureText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(cursorColor(handTracking.gesture).opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private var gestureText: String {
        switch handTracking.gesture {
        case .none: return ""
        case .pointing: return "POINT"
        case .pinch: return "ORBIT"
        case .victory: return "SCROLL"
        case .fourFingers: return "BROWSE"
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(handTracking.isTracking ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(handTracking.isTracking ? "Hand" : "No Hand")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
    }
}
