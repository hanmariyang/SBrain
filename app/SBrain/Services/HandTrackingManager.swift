@preconcurrency import AVFoundation
@preconcurrency import Vision
import SwiftUI
import Combine

// MARK: - Types

enum HandGesture: Equatable, Sendable {
    case none, pointing, pinch, victory, fourFingers
}

enum GestureTarget: Equatable, Sendable {
    case brainMap, viewer
}

enum HandMode: Equatable, Sendable {
    case idle, pointing, orbiting, scrolling, browsing
}

/// Result from background processing → MainActor
struct HandFrameResult: Sendable {
    let gesture: HandGesture
    let mode: HandMode
    let target: GestureTarget
    let pointer: CGPoint
    let delta: CGPoint
    let confidence: Float
    let dwellProgress: CGFloat
    let didDwellSelect: Bool
    let didSwipeLeft: Bool
    let didSwipeRight: Bool
    let scrollSpeed: CGFloat
}

// MARK: - One-Euro Filter (adaptive low-pass — smooth when slow, responsive when fast)

private struct OneEuroFilter {
    private var xPrev: CGFloat = 0
    private var dxPrev: CGFloat = 0
    private var firstTime = true

    // Tuning knobs
    let minCutoff: CGFloat   // low = smoother (default pointer: 1.5)
    let beta: CGFloat        // high = more responsive to fast moves (default: 0.007)
    let dCutoff: CGFloat     // derivative smoothing (fixed 1.0)

    init(minCutoff: CGFloat = 1.5, beta: CGFloat = 0.007, dCutoff: CGFloat = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private func alpha(cutoff: CGFloat, dt: CGFloat) -> CGFloat {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    mutating func filter(_ x: CGFloat, dt: CGFloat) -> CGFloat {
        if firstTime {
            firstTime = false
            xPrev = x; dxPrev = 0
            return x
        }
        let dx = (x - xPrev) / dt
        let aDeriv = alpha(cutoff: dCutoff, dt: dt)
        let dxSmooth = aDeriv * dx + (1 - aDeriv) * dxPrev

        let cutoff = minCutoff + beta * abs(dxSmooth)
        let aSignal = alpha(cutoff: cutoff, dt: dt)
        let result = aSignal * x + (1 - aSignal) * xPrev

        xPrev = result; dxPrev = dxSmooth
        return result
    }

    mutating func reset() { firstTime = true }
}

// MARK: - Background Processor (runs on processing queue, NOT MainActor)

/// All hand tracking computation happens here on a background queue.
/// Only the final HandFrameResult is sent to MainActor.
final class HandProcessor: @unchecked Sendable {

    // ── Tuning constants ──

    // Pointer
    private let confidenceGate: Float = 0.15         // reject low-confidence frames
    private var filterX = OneEuroFilter(minCutoff: 1.2, beta: 0.005)
    private var filterY = OneEuroFilter(minCutoff: 1.2, beta: 0.005)
    private var lastFrameTime: Date?

    // Palm (orbit)
    private var palmFilterX = OneEuroFilter(minCutoff: 0.8, beta: 0.003)
    private var palmFilterY = OneEuroFilter(minCutoff: 0.8, beta: 0.003)
    private var prevSmoothedPalm: CGPoint?

    // Pinch detection
    private let pinchEnterDist: CGFloat = 0.045      // thumb-index distance to enter pinch
    private let pinchExitDist: CGFloat = 0.065        // hysteresis: wider to exit

    // Gesture stabilisation
    private var gestureHistory: [HandGesture] = []
    private let historySize = 7                       // 7-frame buffer
    private let quorumCount = 5                       // need 5/7 agreement
    private var confirmedGesture: HandGesture = .none

    // Mode state machine
    private var mode: HandMode = .idle
    private var modeLockedUntil: Date = .distantPast
    private let modeCooldown: TimeInterval = 0.45     // prevent rapid mode flips
    private var isPinchActive = false                  // hysteresis flag

    // Dwell select
    private var dwellStartTime: Date?
    private let dwellDuration: TimeInterval = 2.0
    private var dwellConfirmed = false

    // Index finger curl select
    private var wasIndexStraight = true
    private var curlCooldown: Date = .distantPast
    private let curlCooldownInterval: TimeInterval = 0.6
    // Curl detection: angle at DIP joint (tip-DIP-PIP)
    private let curlAngleThreshold: CGFloat = 2.3     // radians (~130°); below = curled
    private let straightAngleThreshold: CGFloat = 2.6  // above = straight (hysteresis)

    // Victory scroll
    private var scrollAnchorAngle: CGFloat?
    private var smoothedScrollSpeed: CGFloat = 0
    private let scrollSmoothing: CGFloat = 0.3        // EMA for scroll speed

    // Browse swipe
    private var browseAccumX: CGFloat = 0
    private let swipeThreshold: CGFloat = 0.07

    // Hand loss
    var noHandFrames = 0
    let handLossThreshold = 10

    // ── Reset ──

    func resetDwell() {
        dwellStartTime = nil
        dwellConfirmed = false
    }

    func resetAll() {
        mode = .idle
        modeLockedUntil = .distantPast
        isPinchActive = false
        filterX.reset(); filterY.reset()
        palmFilterX.reset(); palmFilterY.reset()
        prevSmoothedPalm = nil; lastFrameTime = nil
        gestureHistory.removeAll()
        confirmedGesture = .none
        dwellStartTime = nil; dwellConfirmed = false
        wasIndexStraight = true; curlCooldown = .distantPast
        scrollAnchorAngle = nil; smoothedScrollSpeed = 0
        browseAccumX = 0; noHandFrames = 0
    }

    // ── Main process ──

    func process(_ observation: VNHumanHandPoseObservation) -> HandFrameResult? {

        // Confidence gate
        guard observation.confidence >= confidenceGate else {
            handleLost()
            return nil
        }

        guard let thumbTip  = try? observation.recognizedPoint(.thumbTip),
              let indexTip  = try? observation.recognizedPoint(.indexTip),
              let indexDIP  = try? observation.recognizedPoint(.indexDIP),
              let indexPIP  = try? observation.recognizedPoint(.indexPIP),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let middlePIP = try? observation.recognizedPoint(.middlePIP),
              let ringTip   = try? observation.recognizedPoint(.ringTip),
              let ringPIP   = try? observation.recognizedPoint(.ringPIP),
              let pinkyTip  = try? observation.recognizedPoint(.littleTip),
              let pinkyPIP  = try? observation.recognizedPoint(.littlePIP),
              let wrist     = try? observation.recognizedPoint(.wrist),
              let indexMCP  = try? observation.recognizedPoint(.indexMCP),
              let middleMCP = try? observation.recognizedPoint(.middleMCP),
              let ringMCP   = try? observation.recognizedPoint(.ringMCP),
              let pinkyMCP  = try? observation.recognizedPoint(.littleMCP)
        else { return nil }

        let now = Date()
        let dt: CGFloat
        if let prev = lastFrameTime {
            dt = max(CGFloat(now.timeIntervalSince(prev)), 0.016)
        } else {
            dt = 0.033  // first frame ~30fps assumed
        }
        lastFrameTime = now

        // ── 1. Finger extension (angle-based for robustness) ──
        //    Angle at PIP joint: vectors PIP→MCP and PIP→Tip.
        //    Straight ≈ π (180°), curled < 2.0 (~115°)
        let idxExt = jointAngle(tip: indexTip.location,  pip: indexPIP.location,  mcp: indexMCP.location) > 2.2
        let midExt = jointAngle(tip: middleTip.location, pip: middlePIP.location, mcp: middleMCP.location) > 2.2
        let rngExt = jointAngle(tip: ringTip.location,   pip: ringPIP.location,   mcp: ringMCP.location) > 2.0
        let pnkExt = jointAngle(tip: pinkyTip.location,  pip: pinkyPIP.location,  mcp: pinkyMCP.location) > 2.0
        let extCount = (idxExt ? 1 : 0) + (midExt ? 1 : 0) + (rngExt ? 1 : 0) + (pnkExt ? 1 : 0)

        // ── 2. Pinch detection with hysteresis ──
        let thumbIndexDist = hypot(thumbTip.location.x - indexTip.location.x,
                                   thumbTip.location.y - indexTip.location.y)
        if isPinchActive {
            if thumbIndexDist > pinchExitDist { isPinchActive = false }
        } else {
            if thumbIndexDist < pinchEnterDist { isPinchActive = true }
        }

        // ── 3. Raw gesture classification ──
        let raw: HandGesture
        if isPinchActive && extCount <= 1 {
            raw = .pinch
        } else if extCount >= 4 {
            raw = .fourFingers
        } else if idxExt && midExt && !rngExt && !pnkExt {
            raw = .victory
        } else if extCount == 3 && idxExt && midExt {
            raw = .victory   // ring partially extended is OK
        } else if idxExt {
            raw = .pointing
        } else {
            raw = .none      // fist or unrecognised
        }

        // ── 4. Gesture stabilisation (super-majority vote) ──
        gestureHistory.append(raw)
        if gestureHistory.count > historySize { gestureHistory.removeFirst() }
        let voted = superMajorityVote()
        // Only change confirmed gesture when we have strong agreement
        if let v = voted { confirmedGesture = v }
        let stable = confirmedGesture

        // ── 5. Pointer (One-Euro filtered, mirrored) ──
        let rawPtrX = 1.0 - indexTip.location.x
        let rawPtrY = 1.0 - indexTip.location.y
        let smoothX = filterX.filter(rawPtrX, dt: dt)
        let smoothY = filterY.filter(rawPtrY, dt: dt)
        let pointer = CGPoint(x: smoothX, y: smoothY)

        // ── 6. Palm center (One-Euro filtered, mirrored) ──
        let rawPalmX = 1.0 - (wrist.location.x + indexMCP.location.x + middleMCP.location.x + ringMCP.location.x + pinkyMCP.location.x) / 5.0
        let rawPalmY = 1.0 - (wrist.location.y + indexMCP.location.y + middleMCP.location.y + ringMCP.location.y + pinkyMCP.location.y) / 5.0
        let smoothPalmX = palmFilterX.filter(rawPalmX, dt: dt)
        let smoothPalmY = palmFilterY.filter(rawPalmY, dt: dt)
        let palm = CGPoint(x: smoothPalmX, y: smoothPalmY)

        // ── 7. Finger tilt angle for victory scroll ──
        let idxTiltAngle = atan2(indexTip.location.y - indexPIP.location.y,
                                  indexTip.location.x - indexPIP.location.x)
        let midTiltAngle = atan2(middleTip.location.y - middlePIP.location.y,
                                  middleTip.location.x - middlePIP.location.x)
        let fingerTiltAngle = (idxTiltAngle + midTiltAngle) / 2.0

        // ── 8. Index curl angle at DIP (for curl-select) ──
        let curlAngle = jointAngle(tip: indexTip.location, pip: indexDIP.location, mcp: indexPIP.location)

        // ── 9. State machine ──
        let coolingDown = now < modeLockedUntil
        var newMode = mode
        var selectEvent = false
        var swipeL = false, swipeR = false
        var dwellProg: CGFloat = 0
        var scrollSpd: CGFloat = 0

        if !coolingDown {
            switch mode {
            case .idle, .pointing:
                if stable == .pinch {
                    newMode = .orbiting
                    modeLockedUntil = now.addingTimeInterval(modeCooldown)
                    dwellStartTime = nil; dwellConfirmed = false
                } else if stable == .victory {
                    newMode = .scrolling
                    modeLockedUntil = now.addingTimeInterval(modeCooldown)
                    scrollAnchorAngle = fingerTiltAngle
                    smoothedScrollSpeed = 0
                    dwellStartTime = nil; dwellConfirmed = false
                } else if stable == .fourFingers {
                    newMode = .browsing
                    modeLockedUntil = now.addingTimeInterval(modeCooldown)
                    browseAccumX = 0
                    dwellStartTime = nil; dwellConfirmed = false
                } else if stable == .pointing {
                    newMode = .pointing

                    // Curl select: hysteresis on DIP angle
                    if curlAngle > straightAngleThreshold {
                        wasIndexStraight = true
                    } else if curlAngle < curlAngleThreshold && wasIndexStraight && now > curlCooldown {
                        selectEvent = true
                        wasIndexStraight = false
                        curlCooldown = now.addingTimeInterval(curlCooldownInterval)
                    }

                    // Dwell select (fallback)
                    if dwellStartTime == nil { dwellStartTime = now; dwellConfirmed = false }
                    let elapsed = now.timeIntervalSince(dwellStartTime!)
                    dwellProg = CGFloat(min(elapsed / dwellDuration, 1.0))
                    if elapsed >= dwellDuration && !dwellConfirmed {
                        dwellConfirmed = true; selectEvent = true
                    }
                } else {
                    // .none (fist) — go idle, reset dwell
                    newMode = .idle
                    dwellStartTime = nil; dwellConfirmed = false
                }

            case .orbiting:
                // Stay in orbit while pinch is active (raw, not stable — more responsive exit)
                if isPinchActive {
                    newMode = .orbiting
                } else {
                    newMode = .idle
                    modeLockedUntil = now.addingTimeInterval(modeCooldown)
                    prevSmoothedPalm = nil
                }

            case .scrolling:
                if stable == .victory || (idxExt && midExt && !rngExt) {
                    newMode = .scrolling
                    if let anchor = scrollAnchorAngle {
                        let offset = anchor - fingerTiltAngle
                        let deadZone: CGFloat = 0.10  // ~6° dead zone
                        if abs(offset) > deadZone {
                            let effective = offset > 0 ? offset - deadZone : offset + deadZone
                            let rawSpeed = effective * 15.0
                            // EMA smooth
                            smoothedScrollSpeed += (rawSpeed - smoothedScrollSpeed) * scrollSmoothing
                        } else {
                            smoothedScrollSpeed *= 0.7  // decay toward zero
                        }
                        scrollSpd = smoothedScrollSpeed
                    }
                } else {
                    newMode = .idle
                    modeLockedUntil = now.addingTimeInterval(modeCooldown)
                    scrollAnchorAngle = nil; smoothedScrollSpeed = 0
                }

            case .browsing:
                if stable == .fourFingers {
                    newMode = .browsing
                    if let prev = prevSmoothedPalm {
                        browseAccumX += palm.x - prev.x
                    }
                    if browseAccumX > swipeThreshold { swipeR = true; browseAccumX = 0 }
                    else if browseAccumX < -swipeThreshold { swipeL = true; browseAccumX = 0 }
                } else {
                    newMode = .idle
                    modeLockedUntil = now.addingTimeInterval(modeCooldown)
                    browseAccumX = 0
                }
            }
        }

        if newMode != .pointing { dwellProg = 0 }

        // ── 10. Orbit delta (smoothed palm) ──
        let delta: CGPoint
        if newMode == .orbiting, let prev = prevSmoothedPalm {
            delta = CGPoint(x: palm.x - prev.x, y: palm.y - prev.y)
        } else {
            delta = .zero
        }

        let target: GestureTarget = (newMode == .scrolling || newMode == .browsing) ? .viewer : .brainMap
        mode = newMode
        prevSmoothedPalm = palm
        noHandFrames = 0

        return HandFrameResult(
            gesture: stable, mode: newMode, target: target,
            pointer: pointer, delta: delta,
            confidence: observation.confidence,
            dwellProgress: dwellProg, didDwellSelect: selectEvent,
            didSwipeLeft: swipeL, didSwipeRight: swipeR,
            scrollSpeed: scrollSpd
        )
    }

    func handleLost() {
        noHandFrames += 1
        if noHandFrames >= handLossThreshold {
            resetAll()
        }
    }

    // ── Helpers ──

    /// Angle at the middle point (PIP) between vectors PIP→MCP and PIP→Tip (radians 0…π).
    /// Straight finger ≈ π, curled finger < 2.0.
    private func jointAngle(tip: CGPoint, pip: CGPoint, mcp: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: mcp.x - pip.x, y: mcp.y - pip.y)
        let v2 = CGPoint(x: tip.x - pip.x, y: tip.y - pip.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = hypot(v1.x, v1.y)
        let mag2 = hypot(v2.x, v2.y)
        guard mag1 > 0.001 && mag2 > 0.001 else { return .pi }
        return acos(max(-1, min(1, dot / (mag1 * mag2))))
    }

    /// Super-majority vote: need quorumCount out of historySize agreement.
    private func superMajorityVote() -> HandGesture? {
        guard gestureHistory.count >= quorumCount else { return nil }
        var counts: [HandGesture: Int] = [:]
        for g in gestureHistory { counts[g, default: 0] += 1 }
        for (gesture, count) in counts {
            if count >= quorumCount { return gesture }
        }
        return nil  // no super-majority — keep previous confirmedGesture
    }
}

// MARK: - Hand Tracking Manager (MainActor — only UI state)

@MainActor
class HandTrackingManager: NSObject, ObservableObject {
    @Published var isEnabled = false {
        didSet { if isEnabled { start() } else { stop() } }
    }
    @Published var isTracking = false
    @Published var gesture: HandGesture = .none
    @Published var mode: HandMode = .idle
    @Published var gestureTarget: GestureTarget = .brainMap
    @Published var pointerPosition: CGPoint?
    @Published var palmDelta: CGPoint = .zero
    @Published var confidence: Float = 0
    @Published var cameraAuthorized = false
    @Published var dwellProgress: CGFloat = 0
    @Published var didDwellSelect = false
    @Published var didSwipeLeft = false
    @Published var didSwipeRight = false
    @Published var scrollSpeed: CGFloat = 0

    // Pointer change threshold — only push UI updates when moved meaningfully
    private let pointerThreshold: CGFloat = 0.004

    // Background processor (accessed only on processingQueue)
    let processor = HandProcessor()

    // AV
    private var captureSession: AVCaptureSession?
    private let videoOutput = AVCaptureVideoDataOutput()
    let processingQueue = DispatchQueue(label: "com.sbrain.hand-tracking", qos: .userInteractive)
    nonisolated(unsafe) var frameCounter: UInt = 0

    // Vision
    nonisolated let handPoseRequest: VNDetectHumanHandPoseRequest = {
        let req = VNDetectHumanHandPoseRequest()
        req.maximumHandCount = 1
        return req
    }()

    override init() {
        super.init()
        checkCameraAuthorization()
    }

    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in self?.cameraAuthorized = granted }
            }
        default: cameraAuthorized = false
        }
    }

    private func start() {
        guard cameraAuthorized, captureSession == nil else {
            if !cameraAuthorized { checkCameraAuthorization() }
            return
        }
        let session = AVCaptureSession()
        session.sessionPreset = .low
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        guard session.canAddOutput(videoOutput) else { return }
        session.addOutput(videoOutput)
        captureSession = session
        let sess = session
        processingQueue.async { sess.startRunning() }
    }

    private func stop() {
        let sess = captureSession
        processingQueue.async { [processor] in
            sess?.stopRunning()
            processor.resetAll()
        }
        captureSession = nil
        isTracking = false; gesture = .none; mode = .idle; gestureTarget = .brainMap
        pointerPosition = nil; palmDelta = .zero; confidence = 0
        dwellProgress = 0; didDwellSelect = false
        didSwipeLeft = false; didSwipeRight = false; scrollSpeed = 0
    }

    func resetDwell() {
        processingQueue.async { [processor] in processor.resetDwell() }
    }

    // Apply background result to published state (minimal @Published writes)
    func applyFrame(_ f: HandFrameResult) {
        if !isTracking { isTracking = true }
        if gesture != f.gesture { gesture = f.gesture }
        if mode != f.mode { mode = f.mode }
        if gestureTarget != f.target { gestureTarget = f.target }

        // Pointer: only update if moved beyond threshold
        if let cur = pointerPosition {
            if abs(cur.x - f.pointer.x) > pointerThreshold || abs(cur.y - f.pointer.y) > pointerThreshold {
                pointerPosition = f.pointer
            }
        } else {
            pointerPosition = f.pointer
        }

        if f.delta.x != 0 || f.delta.y != 0 || palmDelta != .zero { palmDelta = f.delta }
        if confidence != f.confidence { confidence = f.confidence }
        if abs(dwellProgress - f.dwellProgress) > 0.02 { dwellProgress = f.dwellProgress }
        if f.didDwellSelect { didDwellSelect = true } else if didDwellSelect { didDwellSelect = false }
        if f.didSwipeLeft { didSwipeLeft = true } else if didSwipeLeft { didSwipeLeft = false }
        if f.didSwipeRight { didSwipeRight = true } else if didSwipeRight { didSwipeRight = false }
        if abs(scrollSpeed - f.scrollSpeed) > 0.05 { scrollSpeed = f.scrollSpeed }
    }

    func applyHandLost() {
        if processor.noHandFrames < processor.handLossThreshold { return }
        if isTracking { isTracking = false }
        if gesture != .none { gesture = .none }
        if mode != .idle { mode = .idle }
        if gestureTarget != .brainMap { gestureTarget = .brainMap }
        pointerPosition = nil
        if palmDelta != .zero { palmDelta = .zero }
        if confidence != 0 { confidence = 0 }
        if dwellProgress != 0 { dwellProgress = 0 }
        if didDwellSelect { didDwellSelect = false }
        if didSwipeLeft { didSwipeLeft = false }
        if didSwipeRight { didSwipeRight = false }
        if scrollSpeed != 0 { scrollSpeed = 0 }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension HandTrackingManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame throttle — process every 3rd frame (~10fps from 30fps camera)
        frameCounter &+= 1
        guard frameCounter % 3 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([handPoseRequest])
            if let obs = handPoseRequest.results?.first {
                if let result = processor.process(obs) {
                    Task { @MainActor in self.applyFrame(result) }
                } else {
                    processor.handleLost()
                    Task { @MainActor in self.applyHandLost() }
                }
            } else {
                processor.handleLost()
                Task { @MainActor in self.applyHandLost() }
            }
        } catch {}
    }
}
