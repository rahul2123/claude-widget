import Foundation
import ServiceManagement

/// Thin wrapper over the OS login-item registration. The source of truth is
/// `SMAppService.mainApp.status` (the OS owns it) — never mirrored to UserDefaults.
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log("⚙️ login item \(on ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }

    private static func log(_ message: String) {
        let logFile = "/tmp/claude-usage-widget.log"
        let timestamp = DateFormatter.localizedString(
            from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
        }
    }
}
