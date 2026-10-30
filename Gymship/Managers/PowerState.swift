import Foundation
import Observation
import SwiftUI

/// Adaptive Power on iPhone Air turns Low Power Mode on for us — there is no
/// separate Adaptive Power API. This tracks that flag plus thermal state so
/// the mesh, on-device model, and MapKit work can back off together.
@Observable
@MainActor
final class PowerState {
    var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    var thermalState = ProcessInfo.processInfo.thermalState

    init() {
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.thermalState = ProcessInfo.processInfo.thermalState
            }
        }
    }

    /// Automatic Apple Intelligence work (slot picking) should not run.
    var shouldSkipOnDeviceModel: Bool {
        isLowPowerModeEnabled || thermalState == .serious || thermalState == .critical
    }
}

private struct LowPowerModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isLowPowerModeEnabled: Bool {
        get { self[LowPowerModeKey.self] }
        set { self[LowPowerModeKey.self] = newValue }
    }
}
