import Foundation

struct FolderScanner {

    /// Recursively scan a folder and build a tree of FolderNodes.
    /// Only includes folders that contain .md files (directly or nested) and .md files themselves.
    static func scan(at path: String) -> FolderNode? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        return buildNode(url: url, fm: fm)
    }

    private static func buildNode(url: URL, fm: FileManager) -> FolderNode? {
        let name = url.lastPathComponent
        let path = url.path

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var children: [FolderNode] = []

        // Sort: folders first, then files, alphabetical within each
        let sorted = contents.sorted { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aIsDir != bIsDir { return aIsDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }

        for item in sorted {
            let itemName = item.lastPathComponent
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir {
                // Recurse into subfolder
                if let childFolder = buildNode(url: item, fm: fm) {
                    children.append(childFolder)
                }
            } else if itemName.hasSuffix(".md") {
                // Read preview (first 3 non-empty lines)
                let preview = readPreview(at: item.path)
                let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

                children.append(FolderNode(
                    name: itemName,
                    path: item.path,
                    isFolder: false,
                    preview: preview,
                    modifiedAt: modDate
                ))
            }
        }

        // Skip empty folders (no .md files anywhere inside)
        guard !children.isEmpty else { return nil }

        return FolderNode(
            name: name,
            path: path,
            isFolder: true,
            children: children
        )
    }

    private static func readPreview(at path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)

        return lines.joined(separator: "\n")
    }

    /// Read full content of a file
    static func readContent(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
