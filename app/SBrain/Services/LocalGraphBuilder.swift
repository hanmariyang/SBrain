import Foundation

/// Builds a BrainGraph directly from the local folder tree.
/// No backend/embedding needed — uses folder structure for layout.
///
/// Layout strategy:
///  - Each folder becomes a "cluster" with its own angular region
///  - Files within a folder are arranged in a circle within that cluster
///  - Files in the same folder are connected by synapses (strength = 1.0)
///  - Files in sibling folders get weaker synapses (strength = 0.4)
struct LocalGraphBuilder {

    static func build(from root: FolderNode) -> BrainGraph {
        // 1. Collect all .md files with their parent folder path
        var files: [(node: FolderNode, parentPath: String)] = []
        collectFiles(node: root, parentPath: root.path, into: &files)

        guard !files.isEmpty else {
            return BrainGraph(neurons: [], synapses: [])
        }

        // 2. Group by parent folder
        let grouped = Dictionary(grouping: files, by: { $0.parentPath })
        let folderKeys = grouped.keys.sorted()

        // 3. Assign positions — each folder gets an angular slice
        var neurons: [Neuron] = []
        var folderNeuronIds: [String: [String]] = [:]  // parentPath -> [neuron ids]

        let folderCount = folderKeys.count
        let centerX = 0.5
        let centerY = 0.5

        for (folderIdx, folderPath) in folderKeys.enumerated() {
            guard let folderFiles = grouped[folderPath] else { continue }

            // Folder angle (spread folders evenly around center)
            let folderAngle = (Double(folderIdx) / Double(max(folderCount, 1))) * 2.0 * .pi

            // Distance from center based on depth
            let depth = folderPath.components(separatedBy: "/").count
                      - root.path.components(separatedBy: "/").count
            let radius = 0.15 + Double(depth) * 0.1
            let clusterCenterX = centerX + cos(folderAngle) * radius
            let clusterCenterY = centerY + sin(folderAngle) * radius

            // Place files in a small circle around cluster center
            let fileCount = folderFiles.count
            var ids: [String] = []

            for (fileIdx, file) in folderFiles.enumerated() {
                let fileAngle = (Double(fileIdx) / Double(max(fileCount, 1))) * 2.0 * .pi
                let fileRadius = 0.03 + Double(fileCount) * 0.01
                let x = clusterCenterX + cos(fileAngle) * fileRadius
                let y = clusterCenterY + sin(fileAngle) * fileRadius

                // Clamp to 0..1
                let cx = max(0.05, min(0.95, x))
                let cy = max(0.05, min(0.95, y))

                let contentLen = file.node.preview.count
                let chunkEstimate = max(1, contentLen / 100)

                let neuron = Neuron(
                    id: file.node.path,
                    filename: file.node.name,
                    preview: String(file.node.preview.prefix(80)),
                    x: cx,
                    y: cy,
                    chunkCount: chunkEstimate
                )
                neurons.append(neuron)
                ids.append(file.node.path)
            }

            folderNeuronIds[folderPath] = ids
        }

        // 4. Build synapses
        var synapses: [Synapse] = []

        // Same-folder connections (strong) — cap to neighbor links to avoid O(n²)
        for (_, ids) in folderNeuronIds {
            let count = ids.count
            if count <= 8 {
                // Small folder: fully connected
                for i in 0..<count {
                    for j in (i + 1)..<count {
                        synapses.append(Synapse(source: ids[i], target: ids[j], strength: 0.8))
                    }
                }
            } else {
                // Large folder: ring + hub connections (linear, not quadratic)
                for i in 0..<count {
                    let next = (i + 1) % count
                    synapses.append(Synapse(source: ids[i], target: ids[next], strength: 0.8))
                }
                // Connect first node to a few spread-out nodes
                let step = max(count / 4, 1)
                for k in stride(from: step, to: count, by: step) {
                    synapses.append(Synapse(source: ids[0], target: ids[k], strength: 0.6))
                }
            }
        }

        // Sibling-folder connections (weaker, just 1 connection between clusters)
        let folderList = Array(folderNeuronIds.keys.sorted())
        for i in 0..<folderList.count {
            for j in (i + 1)..<folderList.count {
                // Check if they share a parent
                let parentA = (folderList[i] as NSString).deletingLastPathComponent
                let parentB = (folderList[j] as NSString).deletingLastPathComponent
                guard parentA == parentB else { continue }

                if let idA = folderNeuronIds[folderList[i]]?.first,
                   let idB = folderNeuronIds[folderList[j]]?.first {
                    synapses.append(Synapse(
                        source: idA,
                        target: idB,
                        strength: 0.3
                    ))
                }
            }
        }

        return BrainGraph(neurons: neurons, synapses: synapses)
    }

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
