import ApplicationServices
import CoreGraphics
import Foundation
import UserNotifications
import AIShotShared

/// Real TCC permission checks/requests.
///
/// - Screen Recording: `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`.
/// - Accessibility: `AXIsProcessTrusted` / `AXIsProcessTrustedWithOptions`.
/// - Notifications: `UNUserNotificationCenter`.
public struct SystemPermissions: PermissionsChecking {
    public init() {}

    public func status(of permission: Permission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .notifications:
            return await notificationStatus()
        }
    }

    @discardableResult
    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
            return await status(of: .screenRecording)
        case .accessibility:
            // Use the literal key value to avoid referencing the C global
            // `kAXTrustedCheckOptionPrompt`, which Swift 6 treats as
            // non-concurrency-safe shared mutable state.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return await status(of: .accessibility)
        case .notifications:
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            return granted ? .granted : .denied
        }
    }

    private func notificationStatus() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
