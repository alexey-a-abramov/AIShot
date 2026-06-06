/// Queries and requests the TCC permissions AIShot depends on. Implemented by
/// `SystemPermissions` (real) and by fakes in tests / onboarding previews.
public protocol PermissionsChecking: Sendable {
    /// Current status of a permission (best-effort; macOS can't always
    /// distinguish `.notDetermined` from `.denied`).
    func status(of permission: Permission) async -> PermissionStatus

    /// Requests a permission, returning the resulting status. For Accessibility
    /// this opens System Settings (the user must toggle manually).
    @discardableResult
    func request(_ permission: Permission) async -> PermissionStatus
}
