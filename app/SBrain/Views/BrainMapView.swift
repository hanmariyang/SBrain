import SwiftUI

struct BrainMapView: View {
    @EnvironmentObject var noteStore: NoteStore
    @State private var hoveredNeuronId: String?
    @State private var rotationX: Double = 0.0   // pitch (vertical drag)
    @State private var rotationY: Double = 0.0   // yaw (horizontal drag)
    @State private var dragStartRotX: Double = 0.0
    @State private var dragStartRotY: Double = 0.0
    @State private var zoom: CGFloat = 1.0

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
                        zoom: zoom,
                        searchResultPaths: noteStore.searchResultPaths,
                        onTapNeuron: { id in noteStore.selectFile(path: id) }
                    )
                } else {
                    BrainMapEmptyState(isIngesting: noteStore.isIngesting)
                }
            }
            // Drag to rotate
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        let sensitivity = 0.005
                        rotationY = dragStartRotY + value.translation.width * sensitivity
                        rotationX = dragStartRotX + value.translation.height * sensitivity
                        // Clamp pitch
                        rotationX = max(-.pi / 2, min(.pi / 2, rotationX))
                    }
                    .onEnded { _ in
                        dragStartRotX = rotationX
                        dragStartRotY = rotationY
                    }
            )
            // Scroll to zoom
            .onScrollGesture { delta in
                let newZoom = zoom + delta * 0.01
                zoom = max(0.4, min(3.0, newZoom))
            }
        }
        .clipped()
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
        let view = ScrollDetectorView()
        view.action = action
        return view
    }
    func updateNSView(_ nsView: ScrollDetectorView, context: Context) {
        nsView.action = action
    }
}

private class ScrollDetectorView: NSView {
    var action: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        action?(event.deltaY)
    }
}

// MARK: - 3D Brain Canvas

private struct BrainCanvas3D: View {
    let graph: BrainGraph
    let selectedNeuronId: String?
    @Binding var hoveredNeuronId: String?
    @Binding var rotationX: Double
    @Binding var rotationY: Double
    let zoom: CGFloat
    let searchResultPaths: Set<String>
    let onTapNeuron: (String) -> Void

    private let neuronMap: [String: Neuron]
    private let cappedSynapses: [Synapse]
    private let hasSearchResults: Bool

    @State private var cachedSize: CGSize = .zero
    @State private var autoRotation: Double = 0.0

    init(graph: BrainGraph, selectedNeuronId: String?, hoveredNeuronId: Binding<String?>,
         rotationX: Binding<Double>, rotationY: Binding<Double>, zoom: CGFloat,
         searchResultPaths: Set<String>,
         onTapNeuron: @escaping (String) -> Void) {
        self.graph = graph
        self.selectedNeuronId = selectedNeuronId
        self._hoveredNeuronId = hoveredNeuronId
        self._rotationX = rotationX
        self._rotationY = rotationY
        self.zoom = zoom
        self.searchResultPaths = searchResultPaths
        self.hasSearchResults = !searchResultPaths.isEmpty
        self.onTapNeuron = onTapNeuron
        self.neuronMap = Dictionary(uniqueKeysWithValues: graph.neurons.map { ($0.id, $0) })

        if graph.synapses.count > 600 {
            let sorted = graph.synapses.sorted { $0.strength > $1.strength }
            self.cappedSynapses = Array(sorted.prefix(600))
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
                if let id = hitTest3D(at: location) {
                    onTapNeuron(id)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredNeuronId = hitTest3D(at: location)
                case .ended:
                    hoveredNeuronId = nil
                @unknown default:
                    break
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

    /// Project 3D point to 2D screen with perspective
    private func project(_ neuron: Neuron, _ size: CGSize, _ time: Double) -> (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)? {
        // Auto-rotation (slow continuous)
        let autoY = time * 0.08
        let totalYaw = rotationY + autoY
        let totalPitch = rotationX

        // Rotate around Y axis (yaw)
        var rx = neuron.x * cos(totalYaw) + neuron.z * sin(totalYaw)
        let ry = neuron.y
        var rz = -neuron.x * sin(totalYaw) + neuron.z * cos(totalYaw)

        // Rotate around X axis (pitch)
        let ry2 = ry * cos(totalPitch) - rz * sin(totalPitch)
        let rz2 = ry * sin(totalPitch) + rz * cos(totalPitch)
        rz = rz2

        // Perspective projection
        let fov: Double = 3.0
        let viewerDist: Double = fov
        let perspDenom = viewerDist + rz
        guard perspDenom > 0.3 else { return nil }

        let projScale = viewerDist / perspDenom
        let screenX = size.width / 2 + CGFloat(rx * projScale) * size.width * 0.35 * zoom
        let screenY = size.height / 2 - CGFloat(ry2 * projScale) * size.height * 0.35 * zoom

        // Depth: -1(far) to +1(near), mapped to 0..1
        let normalizedDepth = CGFloat((rz + 1.5) / 3.0)

        return (screenX, screenY, normalizedDepth, CGFloat(projScale))
    }

    // MARK: - Draw Background

    private func drawBackground(_ context: inout GraphicsContext, _ size: CGSize) {
        // Deep space gradient
        let bgRect = CGRect(origin: .zero, size: size)
        let topColor = Color(red: 0.02, green: 0.01, blue: 0.08)
        let midColor = Color(red: 0.03, green: 0.02, blue: 0.06)
        let bottomColor = Color(red: 0.01, green: 0.01, blue: 0.04)
        let grad = Gradient(colors: [topColor, midColor, bottomColor])
        let shading = GraphicsContext.Shading.linearGradient(
            grad,
            startPoint: CGPoint(x: size.width / 2, y: 0),
            endPoint: CGPoint(x: size.width / 2, y: size.height)
        )
        context.fill(Path(bgRect), with: shading)
    }

    // MARK: - Starfield

    private func drawStarfield(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        for i in 0..<30 {
            let seed = Double(i) * 97.31
            let phase = time * 0.015 + seed
            let px = fmod(abs(sin(seed * 1.7) * 7919 + phase * 3), 1.0) * size.width
            let py = fmod(abs(cos(seed * 2.3) * 6131 + phase * 2), 1.0) * size.height
            let pSize: CGFloat = 0.8 + CGFloat(i % 3) * 0.6
            let twinkle = 0.03 + 0.04 * sin(phase * 1.5)
            let rect = CGRect(x: px - pSize / 2, y: py - pSize / 2, width: pSize, height: pSize)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle)))
        }
    }

    // MARK: - Draw Scene (sorted by depth)

    private func drawScene(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        // Project all neurons to screen space
        struct Projected {
            let neuron: Neuron
            let screenX: CGFloat
            let screenY: CGFloat
            let depth: CGFloat
            let scale: CGFloat
            let index: Int
        }

        var projectedNeurons: [Projected] = []
        for (index, neuron) in graph.neurons.enumerated() {
            if let p = project(neuron, size, time) {
                projectedNeurons.append(Projected(
                    neuron: neuron, screenX: p.x, screenY: p.y,
                    depth: p.depth, scale: p.scale, index: index
                ))
            }
        }

        // Sort by depth: far first (painter's algorithm)
        projectedNeurons.sort { $0.depth < $1.depth }

        // Build lookup for screen positions
        var screenPositions: [String: (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)] = [:]
        for p in projectedNeurons {
            screenPositions[p.neuron.id] = (p.screenX, p.screenY, p.depth, p.scale)
        }

        // Draw synapses (behind neurons)
        drawSynapses(&context, size, screenPositions)

        // Draw neurons front-to-back
        for p in projectedNeurons {
            drawNeuron3D(&context, p.neuron, p.screenX, p.screenY, p.depth, p.scale, time, p.index)
        }

        // Draw hover/select label on top
        drawHoverLabel3D(&context, size, screenPositions, time)
    }

    // MARK: - Draw Synapses

    private func drawSynapses(_ context: inout GraphicsContext, _ size: CGSize,
                               _ positions: [String: (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)]) {
        for synapse in cappedSynapses {
            guard let fromPos = positions[synapse.source],
                  let toPos = positions[synapse.target] else { continue }

            let from = CGPoint(x: fromPos.x, y: fromPos.y)
            let to = CGPoint(x: toPos.x, y: toPos.y)

            // Skip if too far apart on screen
            let dx = to.x - from.x
            let dy = to.y - from.y
            if dx * dx + dy * dy > size.width * size.width * 0.25 { continue }

            let avgDepth = (fromPos.depth + toPos.depth) / 2
            let depthFade = max(0.05, Double(avgDepth))

            // Dim synapses when search is active
            let searchDim: Double
            if hasSearchResults {
                let sourceMatch = searchResultPaths.contains(synapse.source)
                let targetMatch = searchResultPaths.contains(synapse.target)
                searchDim = (sourceMatch && targetMatch) ? 1.5 : 0.05
            } else {
                searchDim = 1.0
            }

            let baseOpacity = synapse.strength * 0.35 * depthFade * searchDim
            let lineWidth = (0.3 + synapse.strength * 0.8) * Double(min(fromPos.scale, toPos.scale))

            // Curved synapse
            let midX = (from.x + to.x) / 2 + (from.y - to.y) * 0.12
            let midY = (from.y + to.y) / 2 + (to.x - from.x) * 0.12
            let mid = CGPoint(x: midX, y: midY)

            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: mid)

            let startColor = Color.cyan.opacity(baseOpacity)
            let endColor = Color.purple.opacity(baseOpacity)
            let grad = Gradient(colors: [startColor, endColor])
            let shading = GraphicsContext.Shading.linearGradient(grad, startPoint: from, endPoint: to)
            context.stroke(path, with: shading, lineWidth: max(0.3, lineWidth))
        }
    }

    // MARK: - Draw Neuron (3D)

    private func drawNeuron3D(_ context: inout GraphicsContext, _ neuron: Neuron,
                               _ sx: CGFloat, _ sy: CGFloat, _ depth: CGFloat,
                               _ scale: CGFloat, _ time: Double, _ index: Int) {
        let isHovered = hoveredNeuronId == neuron.id
        let isSelected = selectedNeuronId == neuron.id
        let isHTML = neuron.filename.hasSuffix(".html") || neuron.filename.hasSuffix(".htm")
        let isSearchMatch = hasSearchResults && searchResultPaths.contains(neuron.id)
        let isDimmed = hasSearchResults && !isSearchMatch && !isHovered && !isSelected

        // Depth-based sizing: closer = bigger
        let depthScale = 0.5 + Double(depth) * 0.8
        let baseSize: CGFloat = (12 + CGFloat(min(neuron.chunkCount, 10)) * 1.8) * CGFloat(depthScale)

        // Pulse animation — faster for search matches
        let pulseSpeed = isSearchMatch ? 3.5 : (2.0 + Double(index % 7) * 0.3)
        let pulseAmount = isSearchMatch ? 0.08 : 0.04
        let pulse = 1.0 + pulseAmount * sin(time * pulseSpeed + Double(index))
        let sizeMultiplier: CGFloat = isSearchMatch ? 1.4 : 1.0
        let effectiveSize = baseSize * CGFloat(pulse) * sizeMultiplier

        // Depth-based opacity
        let depthOpacity = max(0.15, Double(depth))
        let coreOpacity: Double
        if isDimmed {
            coreOpacity = 0.08
        } else if isHovered || isSelected || isSearchMatch {
            coreOpacity = 1.0
        } else {
            coreOpacity = 0.4 + depthOpacity * 0.5
        }

        let glowColor = neuronColor(neuron, isHovered: isHovered, isSelected: isSelected, isHTML: isHTML, isSearchMatch: isSearchMatch)

        // Outer glow — larger for search matches
        let glowMultiplier: CGFloat = (isHovered || isSelected) ? 3.0 : (isSearchMatch ? 3.5 : 2.0)
        let glowSize = effectiveSize * glowMultiplier
        let glowOpacity: Double
        if isDimmed {
            glowOpacity = 0.01
        } else if isSearchMatch {
            glowOpacity = 0.4 + 0.15 * sin(time * 2.0)
        } else if isHovered || isSelected {
            glowOpacity = 0.3
        } else {
            glowOpacity = 0.06 * depthOpacity
        }
        let glowRect = CGRect(x: sx - glowSize / 2, y: sy - glowSize / 2, width: glowSize, height: glowSize)
        context.fill(Path(ellipseIn: glowRect), with: .color(glowColor.opacity(glowOpacity)))

        // Core shape
        if isHTML {
            let half = effectiveSize / 2
            let coreRect = CGRect(x: sx - half, y: sy - half, width: effectiveSize, height: effectiveSize)
            let corePath = Path(roundedRect: coreRect, cornerRadius: effectiveSize * 0.25)
            context.fill(corePath, with: .color(glowColor.opacity(coreOpacity * 0.7)))

            let dotSize = effectiveSize * 0.3
            let dotRect = CGRect(x: sx - dotSize / 2, y: sy - dotSize / 2, width: dotSize, height: dotSize)
            context.fill(Path(roundedRect: dotRect, cornerRadius: 1), with: .color(.white.opacity(coreOpacity * 0.6)))
        } else {
            let coreRect = CGRect(x: sx - effectiveSize / 2, y: sy - effectiveSize / 2, width: effectiveSize, height: effectiveSize)
            context.fill(Path(ellipseIn: coreRect), with: .color(glowColor.opacity(coreOpacity * 0.7)))

            let dotSize = effectiveSize * 0.3
            let dotRect = CGRect(x: sx - dotSize / 2, y: sy - dotSize / 2, width: dotSize, height: dotSize)
            context.fill(Path(ellipseIn: dotRect), with: .color(.white.opacity(coreOpacity * 0.7)))
        }
    }

    // MARK: - Hover Label (3D)

    private func drawHoverLabel3D(_ context: inout GraphicsContext, _ size: CGSize,
                                   _ positions: [String: (x: CGFloat, y: CGFloat, depth: CGFloat, scale: CGFloat)],
                                   _ time: Double) {
        let targetId = hoveredNeuronId ?? selectedNeuronId
        guard let targetId, let neuron = neuronMap[targetId],
              let pos = positions[targetId] else { return }

        let isHTML = neuron.filename.hasSuffix(".html") || neuron.filename.hasSuffix(".htm")
        let name = (neuron.filename as NSString).deletingPathExtension
        let ext = isHTML ? "HTML" : "MD"
        let label = "\(name)  \(ext)"

        let styledText = Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        let resolved = context.resolve(styledText)
        let measureSize = resolved.measure(in: CGSize(width: 400, height: 50))

        let hPad: CGFloat = 12
        let vPad: CGFloat = 7
        let bgX = pos.x - measureSize.width / 2 - hPad
        let bgY = pos.y - 30 - measureSize.height / 2 - vPad
        let bgW = measureSize.width + hPad * 2
        let bgH = measureSize.height + vPad * 2
        let bgRect = CGRect(x: bgX, y: bgY, width: bgW, height: bgH)
        context.fill(Path(roundedRect: bgRect, cornerRadius: 8), with: .color(.black.opacity(0.85)))

        // Border glow
        let borderColor: Color = isHTML ? .orange : .cyan
        context.stroke(Path(roundedRect: bgRect, cornerRadius: 8), with: .color(borderColor.opacity(0.4)), lineWidth: 1)

        // File type badge
        let badgeRect = CGRect(x: bgX + bgW - 6, y: bgY - 3, width: 6, height: 6)
        context.fill(Path(ellipseIn: badgeRect), with: .color(borderColor))

        let textPoint = CGPoint(x: pos.x, y: pos.y - 30)
        context.draw(resolved, at: textPoint)
    }

    // MARK: - Hit Testing (3D projected)

    private func hitTest3D(at point: CGPoint) -> String? {
        let s = cachedSize
        guard s.width > 0 else { return nil }

        let time = Date().timeIntervalSinceReferenceDate

        // Build projected list sorted by depth (nearest first for hit testing)
        struct Hit {
            let id: String
            let sx: CGFloat
            let sy: CGFloat
            let depth: CGFloat
            let radius: CGFloat
        }

        var hits: [Hit] = []
        for neuron in graph.neurons {
            guard let p = project(neuron, s, time) else { continue }
            let depthScale = 0.5 + Double(p.depth) * 0.8
            let baseSize = (12 + CGFloat(min(neuron.chunkCount, 10)) * 1.8) * CGFloat(depthScale)
            let radius = max(baseSize / 2, 14)
            hits.append(Hit(id: neuron.id, sx: p.x, sy: p.y, depth: p.depth, radius: radius))
        }

        // Check nearest (highest depth) first
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

    // MARK: - Helpers

    private func neuronColor(_ neuron: Neuron, isHovered: Bool, isSelected: Bool, isHTML: Bool, isSearchMatch: Bool = false) -> Color {
        if isSelected { return .cyan }
        if isHovered { return .white }
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
                .foregroundStyle(
                    .linearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .opacity(0.5)

            Text("Brain Map")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))

            if isIngesting {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(.purple)
                    Text("임베딩 생성 중...").font(.caption).foregroundStyle(.white.opacity(0.4))
                }
            } else {
                Text("폴더를 인덱싱하면 Brain Map이 생성됩니다")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }
}
