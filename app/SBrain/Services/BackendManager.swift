import Foundation
import Combine

class BackendManager: ObservableObject {
    @Published var isRunning = false
    @Published var isDocker = false
    private var process: Process?
    private var healthTimer: Timer?

    func start() {
        // Check if Docker backend is already running on 8765
        checkDockerBackend { [weak self] dockerRunning in
            DispatchQueue.main.async {
                if dockerRunning {
                    self?.isRunning = true
                    self?.isDocker = true
                    print("[BackendManager] Docker backend detected on :8765")
                    self?.startHealthCheck()
                } else {
                    self?.startLocalProcess()
                }
            }
        }
    }

    private func checkDockerBackend(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:8765/api/status/") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            completion(ok)
        }.resume()
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
