import Foundation
import Combine

class BackendManager: ObservableObject {
    @Published var isRunning = false
    @Published var isDocker = false
    private var process: Process?
    private var healthTimer: Timer?

    func start() {
        // Kill any stale local Django from a previous app session
        killStaleProcessOnPort()

        // Check Docker backend — try both IPv4 and IPv6
        checkDockerBackend { [weak self] dockerRunning in
            DispatchQueue.main.async {
                if dockerRunning {
                    self?.isRunning = true
                    self?.isDocker = true
                    print("[BackendManager] Docker backend detected on :8765")
                    self?.startHealthCheck()
                } else {
                    print("[BackendManager] Docker not found, starting local Django")
                    self?.startLocalProcess()
                }
            }
        }
    }

    /// Kill any Python process listening on port 8765 that we didn't start
    private func killStaleProcessOnPort() {
        // Kill our own tracked process
        if let proc = process, proc.isRunning {
            proc.terminate()
            process = nil
            print("[BackendManager] Killed tracked local process")
        }

        // Also kill any orphaned Python process on 8765 (from previous app session)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        task.arguments = ["-ti", ":8765", "-sTCP:LISTEN"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            for pidStr in output.components(separatedBy: "\n") {
                if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)), pid > 0 {
                    // Only kill Python processes (not Docker)
                    let checkTask = Process()
                    checkTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                    checkTask.arguments = ["-p", "\(pid)", "-o", "comm="]
                    let checkPipe = Pipe()
                    checkTask.standardOutput = checkPipe
                    checkTask.standardError = FileHandle.nullDevice
                    try checkTask.run()
                    checkTask.waitUntilExit()
                    let comm = String(data: checkPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if comm.lowercased().contains("python") {
                        kill(pid, SIGTERM)
                        print("[BackendManager] Killed orphaned Python process \(pid) on :8765")
                    }
                }
            }
        } catch {
            // Ignore — no stale process
        }
    }

    private func checkDockerBackend(completion: @escaping (Bool) -> Void) {
        // Try localhost (may resolve IPv6 first on macOS) to detect Docker
        let urls = [
            "http://localhost:8765/api/status/",
            "http://127.0.0.1:8765/api/status/",
        ]

        let group = DispatchGroup()
        var found = false

        for urlStr in urls {
            guard let url = URL(string: urlStr) else { continue }
            group.enter()
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            URLSession.shared.dataTask(with: request) { _, response, _ in
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    found = true
                }
                group.leave()
            }.resume()
        }

        group.notify(queue: .main) {
            completion(found)
        }
    }

    private func startHealthCheck() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkDockerBackend { running in
                DispatchQueue.main.async {
                    if !running && self?.isDocker == true {
                        self?.isRunning = false
                        self?.isDocker = false
                        print("[BackendManager] Docker backend lost, falling back to local")
                        self?.startLocalProcess()
                    }
                }
            }
        }
    }

    private func startLocalProcess() {
        guard process == nil else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3.11")

        let backendDir = findBackendDir()
        proc.currentDirectoryURL = URL(fileURLWithPath: backendDir)
        proc.arguments = ["manage.py", "runserver", "8765", "--noreload"]

        proc.environment = ProcessInfo.processInfo.environment
        proc.environment?["PYTHONPATH"] = backendDir

        // Activate venv
        let venvPython = findVenvPython()
        if FileManager.default.fileExists(atPath: venvPython) {
            proc.executableURL = URL(fileURLWithPath: venvPython)
        }

        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isDocker = false
            }
        }

        do {
            try proc.run()
            process = proc
            DispatchQueue.main.async {
                self.isRunning = true
                self.isDocker = false
            }
        } catch {
            print("[BackendManager] Failed to start backend: \(error)")
        }
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        if !isDocker {
            process?.terminate()
        }
        process = nil
        isRunning = false
        isDocker = false
    }

    deinit {
        stop()
    }

    private func findBackendDir() -> String {
        let candidates = [
            Bundle.main.bundlePath + "/../../../../../backend",
            Bundle.main.bundlePath + "/../../../../../../backend",
            FileManager.default.currentDirectoryPath + "/backend",
            FileManager.default.currentDirectoryPath + "/../backend",
            NSHomeDirectory() + "/Desktop/Deploy/ss/SBrain/backend",
        ]
        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved + "/manage.py") {
                print("[BackendManager] Found backend at: \(resolved)")
                return resolved
            }
        }
        print("[BackendManager] Backend not found in candidates: \(candidates)")
        return candidates.last!
    }

    private func findVenvPython() -> String {
        let candidates = [
            Bundle.main.bundlePath + "/../../../../../venv/bin/python",
            Bundle.main.bundlePath + "/../../../../../../venv/bin/python",
            FileManager.default.currentDirectoryPath + "/venv/bin/python",
            FileManager.default.currentDirectoryPath + "/../venv/bin/python",
            NSHomeDirectory() + "/Desktop/Deploy/ss/SBrain/venv/bin/python",
        ]
        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                print("[BackendManager] Found venv Python at: \(resolved)")
                return resolved
            }
        }
        let systemPythons = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
        ]
        for path in systemPythons {
            if FileManager.default.fileExists(atPath: path) {
                print("[BackendManager] Using system Python: \(path)")
                return path
            }
        }
        return "/usr/bin/python3"
    }
}
