import Foundation

/// FSEvents 기반 파일 시스템 모니터.
/// 프로젝트 폴더를 감시하여 파일 추가/수정/삭제 시 콜백을 호출한다.
@MainActor
class FileMonitor: ObservableObject {

    /// 감시 중인 폴더 경로 → FSEventStream 매핑
    private var streams: [String: FSEventStreamRef] = [:]

    /// Debounce를 위한 보류 중인 변경 경로
    private var pendingChanges: Set<String> = []
    private var debounceTask: Task<Void, Never>?

    /// 파일 변경 시 호출되는 콜백
    var onFilesChanged: (([String]) -> Void)?

    // MARK: - Public API

    /// 프로젝트 폴더에 대한 FSEvents 감시 시작
    func startWatching(path: String) {
        guard streams[path] == nil else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }

        let cfPath = path as CFString
        let pathsToWatch = [cfPath] as CFArray

        // Unmanaged pointer to self for C callback
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: pointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            nil,
            FileMonitor.fsEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // latency: 1초
            UInt32(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer
            )
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        streams[path] = stream
    }

    /// 특정 폴더의 감시 중지
    func stopWatching(path: String) {
        guard let stream = streams.removeValue(forKey: path) else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// 모든 감시 중지
    func stopAll() {
        for path in Array(streams.keys) {
            stopWatching(path: path)
        }
    }

    // MARK: - Internal

    /// FSEvents 콜백에서 호출 — 변경 경로 수집 + debounce
    nonisolated func handleRawEvents(paths: [String]) {
        Task { @MainActor in
            let supportedExtensions: Set<String> = ["md", "html", "htm"]

            for path in paths {
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                // 지원되는 확장자이거나, 디렉토리 변경(확장자 없음)인 경우만 수집
                if supportedExtensions.contains(ext) || ext.isEmpty {
                    pendingChanges.insert(path)
                }
            }

            guard !pendingChanges.isEmpty else { return }

            // Debounce: 1초 후 일괄 처리
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                let changes = Array(pendingChanges)
                pendingChanges.removeAll()
                onFilesChanged?(changes)
            }
        }
    }

    // MARK: - FSEvents C Callback

    /// C 함수 포인터 — FSEventStreamCreate에 전달
    private static let fsEventCallback: FSEventStreamCallback = {
        (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in

        guard let info = clientCallBackInfo else { return }
        let monitor = Unmanaged<FileMonitor>.fromOpaque(info).takeUnretainedValue()

        guard let cfArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

        monitor.handleRawEvents(paths: cfArray)
    }

    deinit {
        // 동기적으로 스트림 정리
        for (_, stream) in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
    }
}
