// MARK: - Update Capability

/// The app has no update channel: nothing checks, downloads, or installs updates.
/// New versions are installed manually from a reviewed release. The single case carries no inputs.
enum UpdateCapability: Equatable, Sendable {
    case unavailable

    static let current = UpdateCapability.unavailable

    var titleKey: String {
        switch self {
        case .unavailable: return "update.unavailable.title"
        }
    }

    var messageKey: String {
        switch self {
        case .unavailable: return "update.unavailable.message"
        }
    }
}
