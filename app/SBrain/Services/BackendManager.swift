import Foundation
import Combine

class BackendManager: ObservableObject {
    @Published var isRunning = false
    private var process: Process?

    func start() {
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
            }
        }

        do {
            try proc.run()
            process = proc
            DispatchQueue.main.async {
                self.isRunning = true
            }
        } catch {
            print("Failed to start backend: \(error)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }

    deinit {
        stop()
    }

    private func findBackendDir() -> String {
        // Look for backend/ relative to the app bundle or working directory
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
        // Fallback to system Python
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
