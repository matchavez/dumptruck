//
//  LaunchAtLoginManager.swift
//  Dumptruck
//
//  Wraps ServiceManagement's SMAppService so the Settings checkbox actually
//  takes effect. SMAppService is the modern API (macOS 13+) and replaces the
//  old, deprecated LSSharedFileList / SMLoginItem dance.
//

import Foundation
import ServiceManagement

enum LaunchAtLoginManager {

    /// True if macOS reports the main app as registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggle launch-at-login state. Returns success; on failure logs and
    /// returns false so the caller can revert UI state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("[Dumptruck] LaunchAtLogin toggle failed: \(error)")
            return false
        }
    }
}
