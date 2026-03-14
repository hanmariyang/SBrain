import Foundation

/// Builds a BrainGraph from one or more folder trees.
/// 3D layout: neurons distributed on a sphere using Fibonacci spiral.
/// Projects get separate regions, folders cluster within each region.
struct LocalGraphBuilder {

    /// Build from multiple root folders (multi-project)
    static func build(from roots: [FolderNode]) -> BrainGraph {
        guard !roots.isEmpty else { return BrainGraph(neurons: [], synapses: []) }

        var allNeurons: [Neuron] = []
        var allSynapses: [Synapse] = []

        if roots.count == 1 {
            let result = buildSingle(from: roots[0], sphereCenter: (0, 0, 0), sphereRadius: 1.0, projectTag: nil)
            allNeurons = result.neurons
            allSynapses = result.synapses
        } else {
            // Multi-project: each project gets a region on the sphere
            for (projIdx, root) in roots.enumerated() {
                let angle = (Double(projIdx) / Double(roots.count)) * 2.0 * .pi
                let regionCX = cos(angle) * 0.5
                let regionCY = 0.0
                let regionCZ = sin(angle) * 0.5
                let regionR = 0.6 / sqrt(Double(roots.count))
                let tag = root.name

                let sub = buildSingle(from: root, sphereCenter: (regionCX, regionCY, regionCZ), sphereRadius: regionR, projectTag: tag)
                allNeurons.append(contentsOf: sub.neurons)
                allSynapses.append(contentsOf: sub.synapses)
            }
        }

        return BrainGraph(neurons: allNeurons, synapses: allSynapses)
    }

    /// Build from a single root (legacy compat)
    static func build(from root: FolderNode) -> BrainGraph {
        return build(from: [root])
    }

    // MARK: - Single project build (3D sphere)

    private static func buildSingle(
        from root: FolderNode,
        sphereCenter: (Double, Double, Double),
        sphereRadius: Double,
        projectTag: String?
    ) -> BrainGraph {
        var files: [(node: FolderNode, parentPath: String)] = []
        collectFiles(node: root, parentPath: root.path, into: &files)

        guard !files.isEmpty else {
            return BrainGraph(neurons: [], synapses: [])
        }

        let grouped = Dictionary(grouping: files, by: { $0.parentPath })
        let folderKeys = grouped.keys.sorted()

        var neurons: [Neuron] = []
        var folderNeuronIds: [String: [String]] = [:]

        let totalFiles = files.count
        var globalIdx = 0

        let (scx, scy, scz) = sphereCenter

        for folderPath in folderKeys {
            guard let folderFiles = grouped[folderPath] else { continue }
            var ids: [String] = []

            for file in folderFiles {
                // Fibonacci sphere point
                let (fx, fy, fz) = fibonacciSpherePoint(index: globalIdx, total: totalFiles)

                // Apply region offset and radius
                let x = scx + fx * sphereRadius
                let y = scy + fy * sphereRadius
                let z = scz + fz * sphereRadius

                let contentLen = file.node.preview.count
                let chunkEstimate = max(1, contentLen / 100)
                let neuronTag = projectTag ?? ""

                let neuron = Neuron(
                    id: file.node.path,
                    filename: file.node.name,
                    preview: String(file.node.preview.prefix(80)),
                    x: x, y: y, z: z,
                    chunkCount: chunkEstimate,
                    projectTag: neuronTag
                )
                neurons.append(neuron)
                ids.append(file.node.path)
                globalIdx += 1
            }

            folderNeuronIds[folderPath] = ids
        }

        // Synapses — same-folder connections
        var synapses: [Synapse] = []

        for (_, ids) in folderNeuronIds {
            let count = ids.count
            if count <= 8 {
                for i in 0..<count {
                    for j in (i + 1)..<count {
                        synapses.append(Synapse(source: ids[i], target: ids[j], strength: 0.8))
                    }
                }
            } else {
                // Ring + hub for large folders
                for i in 0..<count {
                    let next = (i + 1) % count
                    synapses.append(Synapse(source: ids[i], target: ids[next], strength: 0.8))
                }
                let step = max(count / 4, 1)
                for k in stride(from: step, to: count, by: step) {
                    synapses.append(Synapse(source: ids[0], target: ids[k], strength: 0.6))
                }
            }
        }

        // Cross-folder: sibling folder connections
        let folderList = Array(folderNeuronIds.keys.sorted())
        for i in 0..<folderList.count {
            for j in (i + 1)..<folderList.count {
                let parentA = (folderList[i] as NSString).deletingLastPathComponent
                let parentB = (folderList[j] as NSString).deletingLastPathComponent
                guard parentA == parentB else { continue }

                if let idA = folderNeuronIds[folderList[i]]?.first,
                   let idB = folderNeuronIds[folderList[j]]?.first {
                    synapses.append(Synapse(source: idA, target: idB, strength: 0.3))
                }
            }
        }

        return BrainGraph(neurons: neurons, synapses: synapses)
    }

    // MARK: - Fibonacci Sphere

    /// Distributes points evenly on a unit sphere using Fibonacci spiral
    private static func fibonacciSpherePoint(index: Int, total: Int) -> (Double, Double, Double) {
        let goldenRatio = (1.0 + sqrt(5.0)) / 2.0
        let i = Double(index)
        let n = Double(max(total, 1))

        // Latitude: evenly spaced from -1 to 1
        let y = 1.0 - (i / (n - 1)) * 2.0
        let radiusAtY = sqrt(max(0, 1.0 - y * y))

        // Longitude: golden angle increment
        let theta = 2.0 * .pi * i / goldenRatio

        let x = cos(theta) * radiusAtY
        let z = sin(theta) * radiusAtY

        return (x, y, z)
    }

    // MARK: - File Collection

    private static func collectFiles(
        node: FolderNode,
        parentPath: String,
        into result: inout [(node: FolderNode, parentPath: String)]
    ) {
        if !node.isFolder {
            result.append((node: node, parentPath: parentPath))
            return
        }
        for child in node.children {
            if child.isFolder {
                collectFiles(node: child, parentPath: child.path, into: &result)
            } else {
                result.append((node: child, parentPath: node.path))
            }
        }
    }
}
