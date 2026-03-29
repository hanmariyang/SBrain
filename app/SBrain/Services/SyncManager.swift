import Foundation
import CryptoKit

/// macOS → Railway 클라우드 동기화 매니저.
/// FileMonitor 변경 감지 시 변경된 노트를 Railway에 push한다.
@MainActor
class SyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncAt: Date?
    @Published var syncError: String?

    private let api = APIClient.shared

    /// 클라우드 인증 여부
    var isCloudAuthenticated: Bool {
        !api.jwtAccessToken.isEmpty
    }

    // MARK: - Push Changes

    /// 변경된 노트를 Railway에 push
    func pushChanges(changedPaths: [String], deletedPaths: [String], projects: [ProjectFolder]) async {
        guard isCloudAuthenticated else { return }
        guard !changedPaths.isEmpty || !deletedPaths.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        // 변경된 파일 → SyncNote 변환
        let notes: [[String: String]] = changedPaths.compactMap { path in
            guard let content = try? String(contentsOfFile: path, encoding: .utf8),
                  let project = projects.first(where: { path.hasPrefix($0.path) })
            else { return nil }

            let relPath = Self.relativePath(absolutePath: path, projectPath: project.path)
            let noteId = Self.sha256(relPath)

            return [
                "id": noteId,
                "path": relPath,
                "filename": URL(fileURLWithPath: path).lastPathComponent,
                "content": content,
                "updated_at": ISO8601DateFormatter().string(from: Date()),
            ]
        }

        // 삭제된 파일 → ID 변환
        let deletedIds: [String] = deletedPaths.compactMap { path in
            guard let project = projects.first(where: { path.hasPrefix($0.path) })
            else { return nil }
            return Self.sha256(Self.relativePath(absolutePath: path, projectPath: project.path))
        }

        do {
            try await api.syncPush(notes: notes, deletedIds: deletedIds)
            lastSyncAt = Date()
            syncError = nil
            Analytics.syncPush(noteCount: notes.count)
        } catch {
            syncError = error.localizedDescription
            Analytics.syncError(error.localizedDescription)
        }
    }

    // MARK: - Full Sync (앱 시작 시)

    /// 모든 프로젝트의 전체 노트를 Railway에 push
    func fullSync(projects: [ProjectFolder]) async {
        guard isCloudAuthenticated else { return }

        isSyncing = true
        defer { isSyncing = false }

        var allNotes: [[String: String]] = []

        for project in projects {
            guard let root = project.rootFolder else { continue }
            let files = Self.collectFiles(node: root)

            for file in files {
                guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }
                let relPath = Self.relativePath(absolutePath: file.path, projectPath: project.path)
                allNotes.append([
                    "id": Self.sha256(relPath),
                    "path": relPath,
                    "filename": file.name,
                    "content": content,
                    "updated_at": ISO8601DateFormatter().string(from: Date()),
                ])
            }
        }

        guard !allNotes.isEmpty else { return }

        // 100개씩 배치 push (요청 크기 제한 대응)
        let batchSize = 100
        for i in stride(from: 0, to: allNotes.count, by: batchSize) {
            let batch = Array(allNotes[i..<min(i + batchSize, allNotes.count)])
            do {
                try await api.syncPush(notes: batch, deletedIds: [])
            } catch {
                syncError = error.localizedDescription
                return
            }
        }

        lastSyncAt = Date()
        syncError = nil
    }

    // MARK: - Cloud Auth

    /// JWT 로그인
    func login(username: String, password: String) async throws {
        try await api.cloudLogin(username: username, password: password)
        Analytics.authLogin()
    }

    /// 로그아웃
    func logout() {
        api.jwtAccessToken = ""
        api.jwtRefreshToken = ""
    }

    // MARK: - Helpers

    /// 절대경로 → 프로젝트 상대경로
    static func relativePath(absolutePath: String, projectPath: String) -> String {
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        let relative = absolutePath.replacingOccurrences(of: projectPath + "/", with: "")
        return "\(projectName)/\(relative)"
    }

    /// SHA256 해시
    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(32).map { String(format: "%02x", $0) }.joined()
    }

    /// FolderNode 트리에서 파일만 수집
    static func collectFiles(node: FolderNode) -> [FolderNode] {
        var result: [FolderNode] = []
        if !node.isFolder {
            result.append(node)
        }
        for child in node.children {
            result.append(contentsOf: collectFiles(node: child))
        }
        return result
    }
}
