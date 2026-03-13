import SwiftUI

struct BrainMapView: View {
    @EnvironmentObject var noteStore: NoteStore
    @State private var hoveredNeuron: String?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1))
                AmbientParticles()

                if let graph = noteStore.brainGraph, !graph.neurons.isEmpty {
                    graphContent(graph: graph, size: geo.size)
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

    @ViewBuilder
    private func graphContent(graph: BrainGraph, size: CGSize) -> some View {
        Canvas { context, canvasSize in
            drawSynapses(context: context, size: canvasSize, graph: graph)
        }

        ForEach(graph.neurons) { neuron in
            let isSelected = noteStore.selectedFilePath == neuron.id
            NeuronNode(
                neuron: neuron,
                isHovered: hoveredNeuron == neuron.id,
                isSelected: isSelected
            )
            .position(
                x: neuronX(neuron, in: size),
                y: neuronY(neuron, in: size)
            )
            .onHover { h in hoveredNeuron = h ? neuron.id : nil }
            .onTapGesture {
                // neuron.id is the file path (from LocalGraphBuilder)
                noteStore.selectFile(path: neuron.id)
            }
        }
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

    private func neuronX(_ neuron: Neuron, in size: CGSize) -> CGFloat {
        let padding: CGFloat = 80
        return padding + CGFloat(neuron.x) * (size.width - padding * 2)
    }

    private func neuronY(_ neuron: Neuron, in size: CGSize) -> CGFloat {
        let padding: CGFloat = 80
        return padding + CGFloat(neuron.y) * (size.height - padding * 2)
    }

    private func drawSynapses(context: GraphicsContext, size: CGSize, graph: BrainGraph) {
        let neuronMap = Dictionary(uniqueKeysWithValues: graph.neurons.map { ($0.id, $0) })

        for synapse in graph.synapses {
            guard let source = neuronMap[synapse.source],
                  let target = neuronMap[synapse.target] else { continue }

            let from = CGPoint(x: neuronX(source, in: size), y: neuronY(source, in: size))
            let to = CGPoint(x: neuronX(target, in: size), y: neuronY(target, in: size))

            let opacity = synapse.strength * 0.6
            let lineWidth = 0.5 + synapse.strength * 2.0
            let mid = CGPoint(
                x: (from.x + to.x) / 2 + (from.y - to.y) * 0.15,
                y: (from.y + to.y) / 2 + (to.x - from.x) * 0.15
            )

            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: mid)

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [Color.cyan.opacity(opacity), Color.purple.opacity(opacity)]),
                    startPoint: from, endPoint: to
                ),
                lineWidth: lineWidth
            )
        }
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

// MARK: - Neuron Node

struct NeuronNode: View {
    let neuron: Neuron
    let isHovered: Bool
    let isSelected: Bool
    @State private var pulseScale: CGFloat = 1.0

    private var nodeSize: CGFloat {
        24 + CGFloat(min(neuron.chunkCount, 10)) * 3
    }

    private var glowColor: Color {
        if isSelected { return .cyan }
        if isHovered { return .white }
        let hue = (neuron.x + neuron.y) / 2
        return Color(hue: 0.5 + hue * 0.3, saturation: 0.8, brightness: 0.9)
    }

    var body: some View {
        ZStack {
            neuronGlow
            neuronCore
            neuronDot

            if isHovered || isSelected {
                neuronLabel
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: Double.random(in: 2...4)).repeatForever(autoreverses: true)) {
                pulseScale = CGFloat.random(in: 1.03...1.12)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }

    private var neuronGlow: some View {
        Circle()
            .fill(RadialGradient(
                colors: [glowColor.opacity(isHovered || isSelected ? 0.4 : 0.15), .clear],
                center: .center, startRadius: nodeSize * 0.3, endRadius: nodeSize * 1.5
            ))
            .frame(width: nodeSize * 3, height: nodeSize * 3)
            .scaleEffect(pulseScale)
    }

    private var neuronCore: some View {
        Circle()
            .fill(RadialGradient(
                colors: [glowColor.opacity(0.9), glowColor.opacity(0.3)],
                center: .center, startRadius: 0, endRadius: nodeSize * 0.5
            ))
            .frame(width: nodeSize, height: nodeSize)
    }

    private var neuronDot: some View {
        Circle()
            .fill(Color.white.opacity(0.8))
            .frame(width: nodeSize * 0.3, height: nodeSize * 0.3)
    }

    private var neuronLabel: some View {
        VStack(spacing: 2) {
            Text(neuron.filename.replacingOccurrences(of: ".md", with: ""))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            if !neuron.preview.isEmpty {
                Text(neuron.preview)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .offset(y: -nodeSize - 16)
    }
}

// MARK: - Ambient Particles

struct AmbientParticles: View {
    @State private var particles: [Particle] = (0..<30).map { _ in Particle.random() }

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var targetX: CGFloat
        var targetY: CGFloat

        static func random() -> Particle {
            Particle(
                x: .random(in: 0...1), y: .random(in: 0...1),
                size: .random(in: 1...3), opacity: .random(in: 0.05...0.2),
                targetX: .random(in: 0...1), targetY: .random(in: 0...1)
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                Circle()
                    .fill(Color.cyan.opacity(p.opacity))
                    .frame(width: p.size, height: p.size)
                    .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: true)) {
                particles = particles.map { p in
                    var new = p
                    new.x = p.targetX
                    new.y = p.targetY
                    return new
                }
            }
        }
        .allowsHitTesting(false)
    }
}
