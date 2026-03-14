import SwiftUI

struct BrainMapView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var handTracking: HandTrackingManager
    @State private var hoveredNeuronId: String?
    @State private var rotationX: Double = 0.0
    @State private var rotationY: Double = 0.0
    @State private var dragStartRotX: Double = 0.0
    @State private var dragStartRotY: Double = 0.0
    @State private var zoom: CGFloat = 1.0

    // Focus animation
    @State private var focusOffsetYaw: Double = 0    // added to rotationY during focus
    @State private var focusOffsetPitch: Double = 0
    @State private var focusZoomTarget: CGFloat?
    @State private var focusAnimating = false
    @State private var autoRotationPaused = false

    // Immersive transition (0 = overview, 1 = fully immersive)
    @State private var immersiveProgress: Double = 0.0
    @State private var immersiveAnimating = false
    @State private var preImmersiveZoom: CGFloat = 1.0  // saved zoom before entering

    /// Immersive mode when a single project is selected
    var isImmersive: Bool { noteStore.selectedProjectId != nil }

    /// Sphere center for the selected project (for immersive camera placement)
    var sphereCenter: (x: Double, y: Double, z: Double) {
        guard let project = noteStore.selectedProject else { return (0, 0, 0) }
        let projIdx = noteStore.projects.firstIndex(where: { $0.id == project.id }) ?? 0
        let count = noteStore.projects.count
        if count <= 1 { return (0, 0, 0) }
        let angle = (Double(projIdx) / Double(count)) * 2.0 * .pi
        return (cos(angle) * 0.5, 0.0, sin(angle) * 0.5)
    }

    /// Interpolated camera distance: 3.0 (overview) → 0.3 (immersive inside sphere)
    var animatedCamDist: Double {
        3.0 + (0.3 - 3.0) * immersiveProgress  // 3.0 → 0.3
    }

    /// Interpolated zoom multiplier: 1.0 (overview) → 2.8 (immersive)
    var immersiveZoomMultiplier: Double {
        1.0 + (2.8 - 1.0) * immersiveProgress
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: NSColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1))

                if let graph = noteStore.filteredBrainGraph, !graph.neurons.isEmpty {
                    BrainCanvas3D(
                        graph: graph,
                        selectedNeuronId: noteStore.selectedFilePath,
                        hoveredNeuronId: $hoveredNeuronId,
                        rotationX: $rotationX,
                        rotationY: $rotationY,
                        zoom: zoom * CGFloat(immersiveZoomMultiplier),
                        camDist: animatedCamDist,
                        isImmersive: isImmersive,
                        sphereCenter: sphereCenter,
                        autoRotationPaused: autoRotationPaused,
                        focusOffsetYaw: focusOffsetYaw,
                        focusOffsetPitch: focusOffsetPitch,
                        searchResultPaths: noteStore.searchResultPaths,
                        multiSelectedPaths: Set(noteStore.multiSelectedPaths),
                        onTapNeuron: { id, isMultiSelect in
                            if isMultiSelect {
                                noteStore.toggleMultiSelect(path: id)
                            } else {
                                selectAndFocus(id, graph: graph)
                            }
                        }
                    )
                } else {
                    BrainMapEmptyState(isIngesting: noteStore.isIngesting)
                }

                HandCursorOverlay()
            }
            // Drag to rotate
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        cancelFocus()
                        let s = 0.005
                        rotationY = dragStartRotY + value.translation.width * s
                        rotationX = dragStartRotX + value.translation.height * s
                        rotationX = max(-.pi / 2, min(.pi / 2, rotationX))
                    }
                    .onEnded { _ in
                        dragStartRotX = rotationX
                        dragStartRotY = rotationY
                    }
            )
            // Scroll to zoom
            .onScrollGesture { delta in
                cancelFocus()
                zoom = max(0.3, min(5.0, zoom + delta * 0.05))
            }
            // Trackpad pinch-to-zoom
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        cancelFocus()
                        let delta = value.magnification - 1.0
                        zoom = max(0.3, min(5.0, zoom + delta * 0.8))
                    }
            )
            // Immersive mode transition
            .onChange(of: noteStore.selectedProjectId) { _, newId in
                if newId != nil {
                    startImmersiveTransition(entering: true)
                } else {
                    startImmersiveTransition(entering: false)
                }
            }
            // Hand gesture: dwell select (pointing 2초 → multi-select)
            .onChange(of: handTracking.didDwellSelect) { _, selected in
                guard handTracking.gestureTarget == .brainMap else { return }
                if selected, let id = hoveredNeuronId {
                    noteStore.toggleMultiSelect(path: id)
                    handTracking.resetDwell()
                    if let graph = noteStore.filteredBrainGraph {
                        selectAndFocus(id, graph: graph)
                    }
                }
            }
            // Hand gesture: pointer hover (pointing mode, brainMap target only)
            .onChange(of: handTracking.pointerPosition) { _, newPos in
                guard handTracking.isTracking,
                      handTracking.gestureTarget == .brainMap,
                      handTracking.mode == .pointing,
                      let pos = newPos,
                      let graph = noteStore.filteredBrainGraph else { return }
                let pt = CGPoint(x: pos.x * geo.size.width, y: pos.y * geo.size.height)
                let newHovered = hitTestFromHand(at: pt, graph: graph, size: geo.size)
                if newHovered != hoveredNeuronId {
                    handTracking.resetDwell()
                }
                hoveredNeuronId = newHovered
            }
            // Hand gesture: orbit (pinch mode, brainMap target only)
            .onChange(of: handTracking.palmDelta) { _, delta in
                guard handTracking.isTracking,
                      handTracking.gestureTarget == .brainMap,
                      handTracking.mode == .orbiting else { return }
                cancelFocus()
                rotationY += Double(delta.x) * 3.0
                rotationX += Double(delta.y) * 3.0
                rotationX = max(-.pi / 2, min(.pi / 2, rotationX))
                dragStartRotX = rotationX
                dragStartRotY = rotationY
            }
        }
        .clipped()
    }

    // MARK: - Focus Animation

    private func selectAndFocus(_ id: String, graph: BrainGraph) {
        noteStore.selectFile(path: id)
        guard let neuron = graph.neurons.first(where: { $0.id == id }) else { return }

        // Calculate where this neuron is relative to center
        let cx = sphereCenter.x
        let cy = sphereCenter.y
        let cz = sphereCenter.z
        let nx = neuron.x - cx
        let ny = neuron.y - cy
        let nz = neuron.z - cz

        // Target yaw to face the neuron (relative to current rotation, not absolute)
        let targetYaw = atan2(nx, nz)
        let horizDist = sqrt(nx * nx + nz * nz)
        let targetPitch = -atan2(ny, max(horizDist, 0.01))

        // Calculate offset from current rotation to target
        focusOffsetYaw = shortestAngleDiff(from: rotationY, to: targetYaw)
        focusOffsetPitch = max(-.pi / 2, min(.pi / 2, targetPitch)) - rotationX
        focusZoomTarget = isImmersive ? 1.5 : 2.0
        autoRotationPaused = true
        focusAnimating = true
        animateFocusStep()
    }

    private func animateFocusStep() {
        guard focusAnimating else { return }

        let speed = 0.12
        let zoomSpeed: CGFloat = 0.08

        // Lerp offsets toward target
        if abs(focusOffsetYaw) > 0.005 {
            let step = focusOffsetYaw * speed
            rotationY += step
            focusOffsetYaw -= step
            dragStartRotY = rotationY
        } else {
            rotationY += focusOffsetYaw
            dragStartRotY = rotationY
            focusOffsetYaw = 0
        }

        if abs(focusOffsetPitch) > 0.005 {
            let step = focusOffsetPitch * speed
            rotationX += step
            focusOffsetPitch -= step
            rotationX = max(-.pi / 2, min(.pi / 2, rotationX))
            dragStartRotX = rotationX
        } else {
            rotationX += focusOffsetPitch
            rotationX = max(-.pi / 2, min(.pi / 2, rotationX))
            dragStartRotX = rotationX
            focusOffsetPitch = 0
        }

        if let zt = focusZoomTarget {
            let dz = zt - zoom
            if abs(dz) > 0.01 {
                zoom += dz * zoomSpeed
            } else {
                zoom = zt
                focusZoomTarget = nil
            }
        }

        let done = abs(focusOffsetYaw) < 0.005 && abs(focusOffsetPitch) < 0.005 && focusZoomTarget == nil
        if done {
            focusAnimating = false
            // Resume auto-rotation after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if !self.focusAnimating { self.autoRotationPaused = false }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                self.animateFocusStep()
            }
        }
    }

    private func cancelFocus() {
        focusAnimating = false
        focusOffsetYaw = 0
        focusOffsetPitch = 0
        focusZoomTarget = nil
        autoRotationPaused = false
    }

    private func shortestAngleDiff(from a: Double, to b: Double) -> Double {
        var diff = b - a
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        return diff
    }

    // MARK: - Immersive Transition

    private func startImmersiveTransition(entering: Bool) {
        immersiveAnimating = true
        animateImmersiveStep(target: entering ? 1.0 : 0.0)
    }

    private func animateImmersiveStep(target: Double) {
        guard immersiveAnimating else { return }
        let speed = 0.08
        let diff = target - immersiveProgress
        if abs(diff) < 0.005 {
            immersiveProgress = target
            immersiveAnimating = false
            return
        }
        immersiveProgress += diff * speed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            self.animateImmersiveStep(target: target)
        }
    }

    // MARK: - Hand Hit Testing

    private func hitTestFromHand(at point: CGPoint, graph: BrainGraph, size: CGSize) -> String? {
        guard size.width > 0 else { return nil }
        let time = Date().timeIntervalSinceReferenceDate
        let autoY = autoRotationPaused ? 0 : time * (isImmersive ? 0.03 : 0.06)
        let totalYaw = rotationY + autoY
        let totalPitch = rotationX
        let sc = sphereCenter
        let cd = animatedCamDist

        struct Hit { let id: String; let sx: CGFloat; let sy: CGFloat; let depth: CGFloat; let radius: CGFloat }
        var hits: [Hit] = []

        for neuron in graph.neurons {
            let nx = neuron.x - sc.x
            let ny = neuron.y - sc.y
            let nz = neuron.z - sc.z
            let rx = nx * cos(totalYaw) + nz * sin(totalYaw)
            let rz0 = -nx * sin(totalYaw) + nz * cos(totalYaw)
            let ry2 = ny * cos(totalPitch) - rz0 * sin(totalPitch)
            let rz = ny * sin(totalPitch) + rz0 * cos(totalPitch)

            let fov = 3.0
            let perspDenom = fov + cd + rz
            guard perspDenom > 0.2 else { continue }

            let ps = fov / perspDenom
            let w = Double(size.width); let h = Double(size.height)
            let z = Double(zoom) * immersiveZoomMultiplier
            let us = min(w, h) * 0.38
            let sx = CGFloat(w / 2 + rx * ps * us * z)
            let sy = CGFloat(h / 2 - ry2 * ps * us * z)
            let nd = CGFloat((rz + cd + 1.5) / (cd + 3.0))
            let ds = 0.5 + Double(max(0, nd)) * 0.8
            let bs = (12.0 + Double(min(neuron.chunkCount, 10)) * 1.8) * ds
            hits.append(Hit(id: neuron.id, sx: sx, sy: sy, depth: nd, radius: CGFloat(max(bs / 2, 20))))
        }
        hits.sort { $0.depth > $1.depth }
        for hit in hits {
            let dx = point.x - hit.sx; let dy = point.y - hit.sy
            if dx * dx + dy * dy <= hit.radius * hit.radius { return hit.id }
        }
        return nil
    }
}

// MARK: - Scroll Gesture Modifier

extension View {
    func onScrollGesture(action: @escaping (CGFloat) -> Void) -> some View {
        self.background(ScrollDetector(action: action))
    }
}

private struct ScrollDetector: NSViewRepresentable {
    let action: (CGFloat) -> Void
    func makeNSView(context: Context) -> ScrollDetectorView {
        let v = ScrollDetectorView(); v.action = action; return v
    }
    func updateNSView(_ nsView: ScrollDetectorView, context: Context) { nsView.action = action }
}

private class ScrollDetectorView: NSView {
    var action: ((CGFloat) -> Void)?
    override func scrollWheel(with event: NSEvent) { action?(event.deltaY) }
}

// MARK: - 3D Brain Canvas

private struct BrainCanvas3D: View {
    let graph: BrainGraph
    let selectedNeuronId: String?
    @Binding var hoveredNeuronId: String?
    @Binding var rotationX: Double
    @Binding var rotationY: Double
    let zoom: CGFloat
    let camDist: Double
    let isImmersive: Bool
    let sphereCenter: (x: Double, y: Double, z: Double)
    let autoRotationPaused: Bool
    let focusOffsetYaw: Double
    let focusOffsetPitch: Double
    let searchResultPaths: Set<String>
    let multiSelectedPaths: Set<String>
    let onTapNeuron: (String, Bool) -> Void  // (id, isMultiSelect)

    private let neuronMap: [String: Neuron]
    private let cappedSynapses: [Synapse]
    private let hasSearchResults: Bool

    @State private var cachedSize: CGSize = .zero

    init(graph: BrainGraph, selectedNeuronId: String?, hoveredNeuronId: Binding<String?>,
         rotationX: Binding<Double>, rotationY: Binding<Double>, zoom: CGFloat,
         camDist: Double, isImmersive: Bool, sphereCenter: (x: Double, y: Double, z: Double),
         autoRotationPaused: Bool, focusOffsetYaw: Double, focusOffsetPitch: Double,
         searchResultPaths: Set<String>, multiSelectedPaths: Set<String>,
         onTapNeuron: @escaping (String, Bool) -> Void) {
        self.graph = graph
        self.selectedNeuronId = selectedNeuronId
        self._hoveredNeuronId = hoveredNeuronId
        self._rotationX = rotationX
        self._rotationY = rotationY
        self.zoom = zoom
        self.camDist = camDist
        self.isImmersive = isImmersive
        self.sphereCenter = sphereCenter
        self.autoRotationPaused = autoRotationPaused
        self.focusOffsetYaw = focusOffsetYaw
        self.focusOffsetPitch = focusOffsetPitch
        self.searchResultPaths = searchResultPaths
        self.multiSelectedPaths = multiSelectedPaths
        self.hasSearchResults = !searchResultPaths.isEmpty
        self.onTapNeuron = onTapNeuron
        self.neuronMap = Dictionary(uniqueKeysWithValues: graph.neurons.map { ($0.id, $0) })

        if graph.synapses.count > 600 {
            self.cappedSynapses = Array(graph.synapses.sorted { $0.strength > $1.strength }.prefix(600))
        } else {
            self.cappedSynapses = graph.synapses
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: true) { context, size in
                drawBackground(&context, size)
                drawStarfield(&context, size, time)
                drawScene(&context, size, time)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let isCmd = NSEvent.modifierFlags.contains(.command)
                if let id = hitTest3D(at: location) { onTapNeuron(id, isCmd) }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hoveredNeuronId = hitTest3D(at: loc)
                case .ended: hoveredNeuronId = nil
                @unknown default: break
                }
            }
            .overlay {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { cachedSize = geo.size }
                        .onChange(of: geo.size) { cachedSize = $1 }
                }
            }
        }
    }

    // MARK: - 3D Projection

    private func totalYaw(_ time: Double) -> Double {
        // No auto-rotation in immersive mode (makes selection easier)
        if isImmersive || autoRotationPaused { return rotationY }
        return rotationY + time * 0.06
    }

    private func project(_ neuron: Neuron, _ size: CGSize, _ time: Double) -> (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)? {
        let yaw = totalYaw(time)
        let pitch = rotationX

        // Transform neuron relative to sphere center
        let nx = neuron.x - sphereCenter.x
        let ny = neuron.y - sphereCenter.y
        let nz = neuron.z - sphereCenter.z

        // Rotate around Y (yaw)
        let rx = nx * cos(yaw) + nz * sin(yaw)
        let rz0 = -nx * sin(yaw) + nz * cos(yaw)

        // Rotate around X (pitch)
        let ry2 = ny * cos(pitch) - rz0 * sin(pitch)
        let rz = ny * sin(pitch) + rz0 * cos(pitch)

        // Perspective projection
        let fov = 3.0
        let perspDenom = fov + camDist + rz
        guard perspDenom > 0.2 else { return nil }

        let projScale = fov / perspDenom
        let w = Double(size.width)
        let h = Double(size.height)
        let z = Double(zoom)
        let uniformScale = min(w, h) * 0.38
        let screenX = CGFloat(w / 2 + rx * projScale * uniformScale * z)
        let screenY = CGFloat(h / 2 - ry2 * projScale * uniformScale * z)

        // Depth normalized 0..1 (closer = higher)
        let depthRange = max(camDist + 3.0, 1.0)
        let normalizedDepth = CGFloat((rz + camDist + 1.5) / depthRange)

        return (screenX, screenY, max(0, min(1, normalizedDepth)), CGFloat(projScale))
    }

    // MARK: - Draw Background

    private func drawBackground(_ context: inout GraphicsContext, _ size: CGSize) {
        let bgRect = CGRect(origin: .zero, size: size)
        let colors: [Color]
        if isImmersive {
            colors = [
                Color(red: 0.0, green: 0.0, blue: 0.05),
                Color(red: 0.02, green: 0.01, blue: 0.08),
                Color(red: 0.0, green: 0.0, blue: 0.03)
            ]
        } else {
            colors = [
                Color(red: 0.02, green: 0.01, blue: 0.08),
                Color(red: 0.03, green: 0.02, blue: 0.06),
                Color(red: 0.01, green: 0.01, blue: 0.04)
            ]
        }
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: colors),
            startPoint: CGPoint(x: size.width / 2, y: 0),
            endPoint: CGPoint(x: size.width / 2, y: size.height)
        )
        context.fill(Path(bgRect), with: shading)
    }

    // MARK: - Starfield

    private func drawStarfield(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        let starCount = isImmersive ? 60 : 30
        for i in 0..<starCount {
            let seed = Double(i) * 97.31
            let phase = time * 0.015 + seed
            let px = fmod(abs(sin(seed * 1.7) * 7919 + phase * 3), 1.0) * Double(size.width)
            let py = fmod(abs(cos(seed * 2.3) * 6131 + phase * 2), 1.0) * Double(size.height)
            let pSize = 0.8 + Double(i % 3) * 0.6
            let twinkle = isImmersive ? (0.05 + 0.06 * sin(phase * 1.5)) : (0.03 + 0.04 * sin(phase * 1.5))
            let rect = CGRect(x: px - pSize / 2, y: py - pSize / 2, width: pSize, height: pSize)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle)))
        }
    }

    // MARK: - Draw Scene

    private func drawScene(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        struct Projected {
            let neuron: Neuron; let sx: CGFloat; let sy: CGFloat
            let depth: CGFloat; let scale: CGFloat; let index: Int
        }

        var projectedNeurons: [Projected] = []
        for (index, neuron) in graph.neurons.enumerated() {
            if let p = project(neuron, size, time) {
                projectedNeurons.append(Projected(
                    neuron: neuron, sx: p.x, sy: p.y,
                    depth: p.depth, scale: p.scale, index: index
                ))
            }
        }
        projectedNeurons.sort { $0.depth < $1.depth }

        var screenPositions: [String: (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)] = [:]
        for p in projectedNeurons {
            screenPositions[p.neuron.id] = (p.sx, p.sy, p.depth, p.scale)
        }

        drawSynapses(&context, size, screenPositions)
        for p in projectedNeurons {
            drawNeuron3D(&context, p.neuron, p.sx, p.sy, p.depth, p.scale, time, p.index)
        }
        drawHoverLabel3D(&context, size, screenPositions)
    }

    // MARK: - Draw Synapses

    private func drawSynapses(_ context: inout GraphicsContext, _ size: CGSize,
                               _ positions: [String: (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)]) {
        for synapse in cappedSynapses {
            guard let fromPos = positions[synapse.source],
                  let toPos = positions[synapse.target] else { continue }

            let from = CGPoint(x: fromPos.x, y: fromPos.y)
            let to = CGPoint(x: toPos.x, y: toPos.y)
            let ddx = to.x - from.x; let ddy = to.y - from.y
            if ddx * ddx + ddy * ddy > size.width * size.width * 0.25 { continue }

            let avgDepth = Double((fromPos.depth + toPos.depth) / 2)
            let depthFade = max(0.05, avgDepth)

            let searchDim: Double
            if hasSearchResults {
                let sm = searchResultPaths.contains(synapse.source)
                let tm = searchResultPaths.contains(synapse.target)
                searchDim = (sm && tm) ? 1.5 : 0.05
            } else { searchDim = 1.0 }

            let baseOpacity = synapse.strength * 0.35 * depthFade * searchDim
            let lineWidth = (0.3 + synapse.strength * 0.8) * Double(min(fromPos.scale, toPos.scale))
            let midX = (from.x + to.x) / 2 + (from.y - to.y) * 0.12
            let midY = (from.y + to.y) / 2 + (to.x - from.x) * 0.12

            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: CGPoint(x: midX, y: midY))
            let grad = Gradient(colors: [Color.cyan.opacity(baseOpacity), Color.purple.opacity(baseOpacity)])
            context.stroke(path, with: .linearGradient(grad, startPoint: from, endPoint: to), lineWidth: max(0.3, lineWidth))
        }
    }

    // MARK: - Draw Neuron

    private func drawNeuron3D(_ context: inout GraphicsContext, _ neuron: Neuron,
                               _ sx: CGFloat, _ sy: CGFloat, _ depth: CGFloat,
                               _ scale: CGFloat, _ time: Double, _ index: Int) {
        let isHovered = hoveredNeuronId == neuron.id
        let isSelected = selectedNeuronId == neuron.id
        let isMultiSelected = multiSelectedPaths.contains(neuron.id)
        let isHTML = neuron.filename.hasSuffix(".html") || neuron.filename.hasSuffix(".htm")
        let isSearchMatch = hasSearchResults && searchResultPaths.contains(neuron.id)
        let isDimmed = hasSearchResults && !isSearchMatch && !isHovered && !isSelected && !isMultiSelected

        let depthScale = 0.5 + Double(max(0, depth)) * 0.8
        var baseSize = CGFloat((12.0 + Double(min(neuron.chunkCount, 10)) * 1.8) * depthScale)
        if isSelected { baseSize *= 1.5 }
        else if isMultiSelected { baseSize *= 1.25 }

        let highlighted = isSearchMatch || isMultiSelected
        let pulseSpeed = highlighted ? 3.5 : (isSelected ? 1.5 : (2.0 + Double(index % 7) * 0.3))
        let pulseAmt = highlighted ? 0.08 : (isSelected ? 0.06 : 0.04)
        let pulse = 1.0 + pulseAmt * sin(time * pulseSpeed + Double(index))
        let sizeMultiplier: CGFloat = highlighted ? 1.4 : 1.0
        let effectiveSize = baseSize * CGFloat(pulse) * sizeMultiplier

        let depthOpacity = max(0.15, Double(max(0, depth)))
        let coreOpacity: Double
        if isDimmed { coreOpacity = 0.08 }
        else if isHovered || isSelected || highlighted { coreOpacity = 1.0 }
        else { coreOpacity = 0.4 + depthOpacity * 0.5 }

        let glowColor = neuronColor(neuron, isHovered: isHovered, isSelected: isSelected, isHTML: isHTML, isSearchMatch: isSearchMatch, isMultiSelected: isMultiSelected)

        // Outer glow
        let glowMul: CGFloat = isSelected ? 4.0 : (isHovered ? 3.0 : (isSearchMatch ? 3.5 : 2.0))
        let glowSize = effectiveSize * glowMul
        let glowOpacity: Double
        if isDimmed { glowOpacity = 0.01 }
        else if isSelected { glowOpacity = 0.5 + 0.1 * sin(time * 1.2) }
        else if isSearchMatch { glowOpacity = 0.4 + 0.15 * sin(time * 2.0) }
        else if isHovered { glowOpacity = 0.3 }
        else { glowOpacity = 0.06 * depthOpacity }

        let glowRect = CGRect(x: sx - glowSize / 2, y: sy - glowSize / 2, width: glowSize, height: glowSize)
        context.fill(Path(ellipseIn: glowRect), with: .color(glowColor.opacity(glowOpacity)))

        // Selected: pulsing ring
        if isSelected {
            let ringSize = effectiveSize * 2.2
            let ringRect = CGRect(x: sx - ringSize / 2, y: sy - ringSize / 2, width: ringSize, height: ringSize)
            context.stroke(Path(ellipseIn: ringRect), with: .color(.cyan.opacity(0.3 + 0.15 * sin(time * 2.0))), lineWidth: 1.5)
        }

        // Multi-selected: steady ring
        if isMultiSelected && !isSelected {
            let ringSize = effectiveSize * 1.8
            let ringRect = CGRect(x: sx - ringSize / 2, y: sy - ringSize / 2, width: ringSize, height: ringSize)
            context.stroke(Path(ellipseIn: ringRect), with: .color(.mint.opacity(0.5)), lineWidth: 1.2)
        }

        // Core
        let coreRect = CGRect(x: sx - effectiveSize / 2, y: sy - effectiveSize / 2, width: effectiveSize, height: effectiveSize)
        if isHTML {
            context.fill(Path(roundedRect: coreRect, cornerRadius: effectiveSize * 0.25), with: .color(glowColor.opacity(coreOpacity * 0.7)))
        } else {
            context.fill(Path(ellipseIn: coreRect), with: .color(glowColor.opacity(coreOpacity * 0.7)))
        }
        let dotSize = effectiveSize * 0.3
        let dotRect = CGRect(x: sx - dotSize / 2, y: sy - dotSize / 2, width: dotSize, height: dotSize)
        context.fill(Path(ellipseIn: dotRect), with: .color(.white.opacity(coreOpacity * 0.7)))
    }

    // MARK: - Hover Label

    private func drawHoverLabel3D(_ context: inout GraphicsContext, _ size: CGSize,
                                   _ positions: [String: (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)]) {
        let targetId = hoveredNeuronId ?? selectedNeuronId
        guard let targetId, let neuron = neuronMap[targetId],
              let pos = positions[targetId] else { return }

        let isHTML = neuron.filename.hasSuffix(".html") || neuron.filename.hasSuffix(".htm")
        let name = (neuron.filename as NSString).deletingPathExtension
        let label = "\(name)  \(isHTML ? "HTML" : "MD")"

        let styledText = Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        let resolved = context.resolve(styledText)
        let ms = resolved.measure(in: CGSize(width: 400, height: 50))

        let hPad: CGFloat = 12; let vPad: CGFloat = 7
        let bgRect = CGRect(x: pos.x - ms.width / 2 - hPad, y: pos.y - 30 - ms.height / 2 - vPad,
                             width: ms.width + hPad * 2, height: ms.height + vPad * 2)
        context.fill(Path(roundedRect: bgRect, cornerRadius: 8), with: .color(.black.opacity(0.85)))
        let borderColor: Color = isHTML ? .orange : .cyan
        context.stroke(Path(roundedRect: bgRect, cornerRadius: 8), with: .color(borderColor.opacity(0.4)), lineWidth: 1)
        context.draw(resolved, at: CGPoint(x: pos.x, y: pos.y - 30))
    }

    // MARK: - Hit Testing

    private func hitTest3D(at point: CGPoint) -> String? {
        let s = cachedSize
        guard s.width > 0 else { return nil }
        let time = Date().timeIntervalSinceReferenceDate

        struct Hit { let id: String; let sx: CGFloat; let sy: CGFloat; let depth: CGFloat; let radius: CGFloat }
        var hits: [Hit] = []
        for neuron in graph.neurons {
            guard let p = project(neuron, s, time) else { continue }
            let depthScale = 0.5 + Double(max(0, p.depth)) * 0.8
            let baseSize = CGFloat((12.0 + Double(min(neuron.chunkCount, 10)) * 1.8) * depthScale)
            hits.append(Hit(id: neuron.id, sx: p.x, sy: p.y, depth: p.depth, radius: max(baseSize / 2, 14)))
        }
        hits.sort { $0.depth > $1.depth }
        for hit in hits {
            let dx = point.x - hit.sx; let dy = point.y - hit.sy
            if dx * dx + dy * dy <= hit.radius * hit.radius { return hit.id }
        }
        return nil
    }

    // MARK: - Helpers

    private func neuronColor(_ neuron: Neuron, isHovered: Bool, isSelected: Bool, isHTML: Bool, isSearchMatch: Bool = false, isMultiSelected: Bool = false) -> Color {
        if isSelected { return .cyan }
        if isHovered { return .white }
        if isMultiSelected { return .mint }
        if isSearchMatch { return .yellow }
        if isHTML {
            let hue = 0.08 + (neuron.x + neuron.y) / 4 * 0.05
            return Color(hue: hue, saturation: 0.7, brightness: 0.9)
        }
        let hue = 0.5 + (neuron.x + neuron.y) / 4 * 0.3
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }
}

// MARK: - Empty State

struct BrainMapEmptyState: View {
    let isIngesting: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(0.5)
            Text("Brain Map").font(.title2).foregroundStyle(.white.opacity(0.6))
            if isIngesting {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(.purple)
                    Text("임베딩 생성 중...").font(.caption).foregroundStyle(.white.opacity(0.4))
                }
            } else {
                Text("폴더를 인덱싱하면 Brain Map이 생성됩니다").font(.caption).foregroundStyle(.white.opacity(0.3))
            }
        }
    }
}
