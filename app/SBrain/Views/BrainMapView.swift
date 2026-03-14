import SwiftUI

struct BrainMapView: View {
    @EnvironmentObject var noteStore: NoteStore
    @State private var hoveredNeuronId: String?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1))

                if let graph = noteStore.brainGraph, !graph.neurons.isEmpty {
                    BrainCanvas(
                        graph: graph,
                        selectedNeuronId: noteStore.selectedFilePath,
                        hoveredNeuronId: $hoveredNeuronId,
                        onTapNeuron: { id in noteStore.selectFile(path: id) }
                    )
                } else {
                    BrainMapEmptyState(isIngesting: noteStore.isIngesting)
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnifyGesture)
            .gesture(panGesture)
        }
        .clipped()
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = max(0.3, min(3.0, value)) }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                )
            }
            .onEnded { _ in dragStart = offset }
    }
}

// MARK: - Brain Canvas (single Canvas for all rendering)

private struct BrainCanvas: View {
    let graph: BrainGraph
    let selectedNeuronId: String?
    @Binding var hoveredNeuronId: String?
    let onTapNeuron: (String) -> Void

    private let neuronMap: [String: Neuron]
    private let cappedSynapses: [Synapse]

    @State private var cachedSize: CGSize = .zero

    init(graph: BrainGraph, selectedNeuronId: String?, hoveredNeuronId: Binding<String?>, onTapNeuron: @escaping (String) -> Void) {
        self.graph = graph
        self.selectedNeuronId = selectedNeuronId
        self._hoveredNeuronId = hoveredNeuronId
        self.onTapNeuron = onTapNeuron
        self.neuronMap = Dictionary(uniqueKeysWithValues: graph.neurons.map { ($0.id, $0) })

        if graph.synapses.count > 500 {
            let sorted = graph.synapses.sorted { $0.strength > $1.strength }
            self.cappedSynapses = Array(sorted.prefix(500))
        } else {
            self.cappedSynapses = graph.synapses
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: true) { context, size in
                drawBackground(&context, size)
                drawParticles(&context, size, time)
                drawAllSynapses(&context, size)
                drawAllNeurons(&context, size, time)
                drawHoverLabel(&context, size)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredNeuronId = hitTest(at: location)
                case .ended:
                    hoveredNeuronId = nil
                @unknown default:
                    break
                }
            }
            .onTapGesture { location in
                if let id = hitTest(at: location) {
                    onTapNeuron(id)
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

    // MARK: - Hit Testing

    private func hitTest(at point: CGPoint) -> String? {
        let s = cachedSize
        guard s.width > 0 else { return nil }
        for neuron in graph.neurons {
            let nx = posX(neuron, s)
            let ny = posY(neuron, s)
            let radius = max(nodeRadius(neuron), 20)
            let dx = point.x - nx
            let dy = point.y - ny
            if dx * dx + dy * dy <= radius * radius {
                return neuron.id
            }
        }
        return nil
    }

    // MARK: - Draw Background

    private func drawBackground(_ context: inout GraphicsContext, _ size: CGSize) {
        let bgColor = Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1))
        let bgRect = CGRect(origin: .zero, size: size)
        context.fill(Path(bgRect), with: .color(bgColor))
    }

    // MARK: - Draw Particles

    private func drawParticles(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        for i in 0..<20 {
            let seed = Double(i) * 137.508
            let phase = time * 0.02 + seed
            let px = (sin(phase * 0.7 + seed) * 0.5 + 0.5) * size.width
            let py = (cos(phase * 0.5 + seed * 1.3) * 0.5 + 0.5) * size.height
            let pSize: CGFloat = 1.5 + CGFloat(i % 3)
            let pOpacity = 0.06 + 0.08 * sin(phase * 2)
            let rect = CGRect(x: px - pSize / 2, y: py - pSize / 2, width: pSize, height: pSize)
            let pColor = Color.cyan.opacity(pOpacity)
            context.fill(Path(ellipseIn: rect), with: .color(pColor))
        }
    }

    // MARK: - Draw Synapses

    private func drawAllSynapses(_ context: inout GraphicsContext, _ size: CGSize) {
        let maxDistSq = size.width * size.width * 0.5

        for synapse in cappedSynapses {
            guard let source = neuronMap[synapse.source],
                  let target = neuronMap[synapse.target] else { continue }

            let fromX = posX(source, size)
            let fromY = posY(source, size)
            let toX = posX(target, size)
            let toY = posY(target, size)

            let dx = toX - fromX
            let dy = toY - fromY
            if dx * dx + dy * dy > maxDistSq { continue }

            let from = CGPoint(x: fromX, y: fromY)
            let to = CGPoint(x: toX, y: toY)

            let midX = (fromX + toX) / 2 + (fromY - toY) * 0.15
            let midY = (fromY + toY) / 2 + (toX - fromX) * 0.15
            let mid = CGPoint(x: midX, y: midY)

            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: mid)

            let opacity = synapse.strength * 0.5
            let lw = 0.5 + synapse.strength * 1.5
            let startColor = Color.cyan.opacity(opacity)
            let endColor = Color.purple.opacity(opacity)
            let grad = Gradient(colors: [startColor, endColor])
            let shading = GraphicsContext.Shading.linearGradient(grad, startPoint: from, endPoint: to)
            context.stroke(path, with: shading, lineWidth: lw)
        }
    }

    // MARK: - Draw Neurons

    private func drawAllNeurons(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        for (index, neuron) in graph.neurons.enumerated() {
            drawSingleNeuron(&context, size, time, neuron, index)
        }
    }

    private func drawSingleNeuron(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double, _ neuron: Neuron, _ index: Int) {
        let cx = posX(neuron, size)
        let cy = posY(neuron, size)
        let baseSize = nodeRadius(neuron)
        let isHovered = hoveredNeuronId == neuron.id
        let isSelected = selectedNeuronId == neuron.id

        let pulse = 1.0 + 0.06 * sin(time * (2.0 + Double(index % 7) * 0.3) + Double(index))
        let effectiveSize = baseSize * CGFloat(pulse)

        let glowColor = neuronColor(neuron, isHovered: isHovered, isSelected: isSelected)
        let glowOpacity: Double = (isHovered || isSelected) ? 0.35 : 0.12

        // Outer glow
        let glowDiameter = effectiveSize * 2.5
        let glowRect = CGRect(x: cx - glowDiameter / 2, y: cy - glowDiameter / 2, width: glowDiameter, height: glowDiameter)
        let glowShading = Color(glowColor).opacity(glowOpacity)
        context.fill(Path(ellipseIn: glowRect), with: .color(glowShading))

        // Core
        let coreRect = CGRect(x: cx - effectiveSize / 2, y: cy - effectiveSize / 2, width: effectiveSize, height: effectiveSize)
        let coreShading = Color(glowColor).opacity(0.6)
        context.fill(Path(ellipseIn: coreRect), with: .color(coreShading))

        // Center dot
        let dotSize = effectiveSize * 0.3
        let dotRect = CGRect(x: cx - dotSize / 2, y: cy - dotSize / 2, width: dotSize, height: dotSize)
        let dotColor = Color.white.opacity(0.8)
        context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
    }

    // MARK: - Draw Hover Label

    private func drawHoverLabel(_ context: inout GraphicsContext, _ size: CGSize) {
        let targetId = hoveredNeuronId ?? selectedNeuronId
        guard let targetId, let neuron = neuronMap[targetId] else { return }

        let cx = posX(neuron, size)
        let cy = posY(neuron, size)
        let nSize = nodeRadius(neuron)
        let label = neuron.filename.replacingOccurrences(of: ".md", with: "")

        let styledText = Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
        let resolved = context.resolve(styledText)
        let measureSize = resolved.measure(in: CGSize(width: 300, height: 50))

        let hPad: CGFloat = 10
        let vPad: CGFloat = 6
        let bgX = cx - measureSize.width / 2 - hPad
        let bgY = cy - nSize - 20 - measureSize.height / 2 - vPad
        let bgW = measureSize.width + hPad * 2
        let bgH = measureSize.height + vPad * 2
        let bgRect = CGRect(x: bgX, y: bgY, width: bgW, height: bgH)
        let bgPath = Path(roundedRect: bgRect, cornerRadius: 8)
        let bgColor = Color.black.opacity(0.75)
        context.fill(bgPath, with: .color(bgColor))

        let textPoint = CGPoint(x: cx, y: cy - nSize - 20)
        context.draw(resolved, at: textPoint)
    }

    // MARK: - Helpers

    private func neuronColor(_ neuron: Neuron, isHovered: Bool, isSelected: Bool) -> Color {
        if isSelected { return .cyan }
        if isHovered { return .white }
        let hue = 0.5 + (neuron.x + neuron.y) / 2 * 0.3
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }

    private func nodeRadius(_ neuron: Neuron) -> CGFloat {
        24 + CGFloat(min(neuron.chunkCount, 10)) * 3
    }

    private func posX(_ neuron: Neuron, _ size: CGSize) -> CGFloat {
        let padding: CGFloat = 80
        return padding + CGFloat(neuron.x) * (size.width - padding * 2)
    }

    private func posY(_ neuron: Neuron, _ size: CGSize) -> CGFloat {
        let padding: CGFloat = 80
        return padding + CGFloat(neuron.y) * (size.height - padding * 2)
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
