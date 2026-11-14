import AppKit
import DockCore

extension DockModel {
    func recordSwitch(_ profile: Profile, stage: SwitchDiagnosticStage, attempt: Int? = nil, code: SwitchFailureCode? = nil, exitStatus: Int32? = nil) {
        guard let provider = DesktopProfileApp(rawValue: profile.kind.rawValue) else { return }
        if switchingTargets[profile.kind] == profile.id { switchStages[profile.kind] = stage }
        guard preferences.switchDiagnosticsEnabled != false else { return }
        let journal = switchDiagnosticLog
        let key = profile.id
        let recovering = diagnosticWriteFailed
        diagnosticQueue.async { [weak self] in
            do {
                try journal.append(profileKey: key, provider: provider, stage: stage, attempt: attempt, code: code, exitStatus: exitStatus)
                if recovering { Task { @MainActor [weak self] in self?.diagnosticWriteFailed = false } }
            } catch {
                Task { @MainActor [weak self] in
                    if self?.diagnosticWriteFailed != true { self?.diagnosticWriteFailed = true }
                }
            }
        }
    }
    func revealSwitchDiagnostics() {
        let directory = switchDiagnosticLog.directory
        if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        } else { diagnosticWriteFailed = true }
    }
}
