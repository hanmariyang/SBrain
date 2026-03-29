import SwiftUI

// MARK: - iOS Brain Map View (Touch Gestures)

struct IOSBrainMapView: View {
    @EnvironmentObject var noteStore: NoteStore

    @State private var selectedNeuronId: String?
    @State private var rotationX: Double = 0.15
    @State private var rotationY: Double = 0.0
    @State private var zoom: CGFloat = 1.0
    @State private var autoRotationPaused = false
    @State private var userHasInteracted = false

    // Drag tracking
    @State private var dragStartRotX: Double = 0.0
    @State private var dragStartRotY: Double = 0.0

    // Focus animation
    @State private var focusOffsetYaw: Double = 0
    @State private var focusOffsetPitch: Double = 0
    @State private var focusZoomTarget: CGFloat?
    @State private var focusAnimating = false

    // Detail sheet
    @State private var showDetailSheet = false
    @State private var selectedPath: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SB.Colors.bgPrimary

                if let graph = noteStore.filteredBrainGraph, !graph.neurons.isEmpty {
                    IOSBrainCanvas(
                        graph: graph,
                        selectedNeuronId: selectedNeuronId,
                        rotationX: rotationX,
                        rotationY: rotationY,
                        zoom: zoom,
                        autoRotationPaused: autoRotationPaused || userHasInteracted,
                        size: geo.size,
                        searchResultPaths: noteStore.searchResultPaths,
                        onTapNeuron: { id in
                            selectAndFocus(id, graph: graph)
                        }
                    )
                } else {
                    IOSBrainEmptyState(isIngesting: noteStore.isIngesting)
                }
            }
            // 1-finger drag -> rotate
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        cancelFocus()
                        userHasInteracted = true
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
            // Pinch -> zoom
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        cancelFocus()
                        userHasInteracted = true
                        let delta = value.magnification - 1.0
                        zoom = max(0.3, min(5.0, zoom + delta * 0.8)
                        )
                    }
            )
        }
        .sheet(isPresented: $showDetailSheet) {
            if let path = selectedPath {
                NavigationStack {
                    IOSNoteDetailView(path: path)
                        .navigationTitle(URL(fileURLWithPath: path).lastPathComponent)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showDetailSheet = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Focus Animation

    private func selectAndFocus(_ id: String, graph: BrainGraph) {
        selectedNeuronId = id
        selectedPath = id
        noteStore.selectFile(path: id)
        showDetailSheet = true

        guard let neuron = graph.neurons.first(where: { $0.id == id }) else { return }

        let targetYaw = atan2(neuron.x, neuron.z)
        let horizDist = sqrt(neuron.x * neuron.x + neuron.z * neuron.z)
        let targetPitch = -atan2(neuron.y, max(horizDist, 0.01))

        focusOffsetYaw = shortestAngleDiff(from: rotationY, to: targetYaw)
        focusOffsetPitch = max(-.pi / 2, min(.pi / 2, targetPitch)) - rotationX
        focusZoomTarget = 2.0
        autoRotationPaused = true
        focusAnimating = true
        animateFocusStep()
    }

    private func animateFocusStep() {
        guard focusAnimating else { return }
        let speed = 0.12
        let zoomSpeed: CGFloat = 0.08

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
}

// MARK: - iOS Brain Canvas (Canvas + TimelineView)

private struct IOSBrainCanvas: View {
    let graph: BrainGraph
    let selectedNeuronId: String?
    let rotationX: Double
    let rotationY: Double
    let zoom: CGFloat
    let autoRotationPaused: Bool
    let size: CGSize
    let searchResultPaths: Set<String>
    let onTapNeuron: (String) -> Void

    private let neuronMap: [String: Neuron]
    private let cappedSynapses: [Synapse]
    private let camDist: Double = 3.0

    init(graph: BrainGraph, selectedNeuronId: String?, rotationX: Double, rotationY: Double,
         zoom: CGFloat, autoRotationPaused: Bool, size: CGSize,
         searchResultPaths: Set<String>, onTapNeuron: @escaping (String) -> Void) {
        self.graph = graph
        self.selectedNeuronId = selectedNeuronId
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.zoom = zoom
        self.autoRotationPaused = autoRotationPaused
        self.size = size
        self.searchResultPaths = searchResultPaths
        self.onTapNeuron = onTapNeuron
        self.neuronMap = Dictionary(uniqueKeysWithValues: graph.neurons.map { ($0.id, $0) })

        if graph.synapses.count > 400 {
            self.cappedSynapses = Array(graph.synapses.sorted { $0.strength > $1.strength }.prefix(400))
        } else {
            self.cappedSynapses = graph.synapses
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: true) { context, canvasSize in
                drawBackground(&context, canvasSize)
                drawStarfield(&context, canvasSize, time)
                drawScene(&context, canvasSize, time)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let id = hitTest(at: location) { onTapNeuron(id) }
            }
        }
    }

    // MARK: - 3D Projection

    private func totalYaw(_ time: Double) -> Double {
        if autoRotationPaused { return rotationY }
        return rotationY + time * 0.06
    }

    private func project(_ neuron: Neuron, _ canvasSize: CGSize, _ time: Double) -> (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)? {
        let yaw = totalYaw(time)
        let pitch = rotationX

        let nx = neuron.x
        let ny = neuron.y
        let nz = neuron.z

        let rx = nx * cos(yaw) + nz * sin(yaw)
        let rz0 = -nx * sin(yaw) + nz * cos(yaw)
        let ry2 = ny * cos(pitch) - rz0 * sin(pitch)
        let rz = ny * sin(pitch) + rz0 * cos(pitch)

        let fov = 3.0
        let perspDenom = fov + camDist + rz
        guard perspDenom > 0.2 else { return nil }

        let projScale = fov / perspDenom
        let w = Double(canvasSize.width)
        let h = Double(canvasSize.height)
        let z = Double(zoom)
        let uniformScale = min(w, h) * 0.38
        let screenX = CGFloat(w / 2 + rx * projScale * uniformScale * z)
        let screenY = CGFloat(h / 2 - ry2 * projScale * uniformScale * z)

        let depthRange = max(camDist + 3.0, 1.0)
        let normalizedDepth = CGFloat((rz + camDist + 1.5) / depthRange)

        return (screenX, screenY, max(0, min(1, normalizedDepth)), CGFloat(projScale))
    }

    // MARK: - Draw

    private func drawBackground(_ context: inout GraphicsContext, _ size: CGSize) {
        let bgRect = CGRect(origin: .zero, size: size)
        let colors: [Color] = [
            Color(hex: "FAF8F5"),
            Color(hex: "F2EDE8"),
            Color(hex: "EBE5DE")
        ]
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: colors),
            startPoint: CGPoint(x: size.width / 2, y: 0),
            endPoint: CGPoint(x: size.width / 2, y: size.height)
        )
        context.fill(Path(bgRect), with: shading)
    }

    private func drawStarfield(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        let starCount = 15
        for i in 0..<starCount {
            let seed = Double(i) * 97.31
            let phase = time * 0.012 + seed
            let px = fmod(abs(sin(seed * 1.7) * 7919 + phase * 2), 1.0) * Double(size.width)
            let py = fmod(abs(cos(seed * 2.3) * 6131 + phase * 1.5), 1.0) * Double(size.height)
            let pSize = 1.0 + Double(i % 3) * 0.5
            let twinkle = 0.06 + 0.05 * sin(phase * 1.2)
            let rect = CGRect(x: px - pSize / 2, y: py - pSize / 2, width: pSize, height: pSize)
            let color: Color = i % 3 == 0 ? Color(hex: "C4973B") : Color(hex: "8FA3C4")
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(twinkle)))
        }
    }

    private func drawScene(_ context: inout GraphicsContext, _ canvasSize: CGSize, _ time: Double) {
        struct Projected {
            let neuron: Neuron; let sx: CGFloat; let sy: CGFloat
            let depth: CGFloat; let scale: CGFloat
        }

        var projectedNeurons: [Projected] = []
        for neuron in graph.neurons {
            if let p = project(neuron, canvasSize, time) {
                projectedNeurons.append(Projected(
                    neuron: neuron, sx: p.x, sy: p.y,
                    depth: p.depth, scale: p.scale
                ))
            }
        }
        projectedNeurons.sort { $0.depth < $1.depth }

        var screenPositions: [String: (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)] = [:]
        for p in projectedNeurons {
            screenPositions[p.neuron.id] = (p.sx, p.sy, p.depth, p.scale)
        }

        // Draw synapses
        for synapse in cappedSynapses {
            guard let fromPos = screenPositions[synapse.source],
                  let toPos = screenPositions[synapse.target] else { continue }
            let from = CGPoint(x: fromPos.x, y: fromPos.y)
            let to = CGPoint(x: toPos.x, y: toPos.y)
            let avgDepth = (fromPos.depth + toPos.depth) / 2
            let alpha = 0.03 + Double(avgDepth) * 0.08
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(Color(hex: "D4DCE8").opacity(alpha)), lineWidth: 0.5)
        }

        // Draw neurons
        for p in projectedNeurons {
            let isSelected = p.neuron.id == selectedNeuronId
            let isSearchResult = !searchResultPaths.isEmpty && searchResultPaths.contains(p.neuron.id)
            let depthScale = 0.5 + Double(max(0, p.depth)) * 0.8
            let baseSize = (10.0 + Double(min(p.neuron.chunkCount, 10)) * 1.5) * depthScale
            let nodeAlpha = 0.3 + Double(p.depth) * 0.7

            let rect = CGRect(
                x: Double(p.sx) - baseSize / 2,
                y: Double(p.sy) - baseSize / 2,
                width: baseSize,
                height: baseSize
            )

            // Glow for selected / search result
            if isSelected || isSearchResult {
                let glowColor = isSelected ? SB.Colors.gold600 : SB.Colors.accentBlue
                let glowRect = rect.insetBy(dx: -4, dy: -4)
                context.fill(Path(ellipseIn: glowRect), with: .color(glowColor.opacity(0.3)))
            }

            // Neuron fill
            let fillColor: Color
            if isSelected {
                fillColor = SB.Colors.gold600
            } else if isSearchResult {
                fillColor = SB.Colors.accentBlue
            } else {
                fillColor = Color(hex: "2D4470")
            }
            context.fill(Path(ellipseIn: rect), with: .color(fillColor.opacity(nodeAlpha)))

            // Label for selected neuron
            if isSelected {
                let name = (p.neuron.filename as NSString).deletingPathExtension
                let text = Text(name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SB.Colors.navy900)
                context.draw(context.resolve(text), at: CGPoint(x: p.sx, y: p.sy - CGFloat(baseSize / 2) - 8))
            }
        }
    }

    // MARK: - Hit Test

    private func hitTest(at point: CGPoint) -> String? {
        let time = Date().timeIntervalSinceReferenceDate
        struct Hit { let id: String; let depth: CGFloat; let radius: CGFloat; let sx: CGFloat; let sy: CGFloat }
        var hits: [Hit] = []

        for neuron in graph.neurons {
            guard let p = project(neuron, size, time) else { continue }
            let depthScale = 0.5 + Double(max(0, p.depth)) * 0.8
            let baseSize = (10.0 + Double(min(neuron.chunkCount, 10)) * 1.5) * depthScale
            // Increase tap target for touch
            let tapRadius = CGFloat(max(baseSize / 2, 22))
            hits.append(Hit(id: neuron.id, depth: p.depth, radius: tapRadius, sx: p.x, sy: p.y))
        }

        hits.sort { $0.depth > $1.depth }
        for hit in hits {
            let dx = point.x - hit.sx
            let dy = point.y - hit.sy
            if dx * dx + dy * dy <= hit.radius * hit.radius {
                return hit.id
            }
        }
        return nil
    }
}

// MARK: - Empty State

private struct IOSBrainEmptyState: View {
    let isIngesting: Bool

    var body: some View {
        VStack(spacing: SB.Space.lg) {
            Image(systemName: "brain")
                .font(.system(size: 56))
                .foregroundStyle(
                    .linearGradient(
                        colors: [SB.Colors.navy700, SB.Colors.gold600],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.4)

            if isIngesting {
                VStack(spacing: SB.Space.sm) {
                    Text("Memorizing...")
                        .font(SB.Font.titleMd())
                        .foregroundStyle(SB.Colors.navy500)
                    ProgressView()
                        .tint(SB.Colors.gold600)
                }
            } else {
                Text("No neurons yet")
                    .font(SB.Font.titleMd())
                    .foregroundStyle(SB.Colors.navy500)

                Text("Add projects from macOS app\nto see your Brain Map here.")
                    .font(SB.Font.bodySm())
                    .foregroundStyle(SB.Colors.navy300)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
