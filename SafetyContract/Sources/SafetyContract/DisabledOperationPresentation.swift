public struct DisabledOperationPresentation: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case informational
    }

    public let tone: Tone
    public let title: String
    public let message: String
    public let actionTitle: String

    public static func forOperation(_ operation: UnsupportedOperation) -> Self {
        switch operation {
        case .permanentDeletion:
            presentation(
                title: "Permanent deletion is unavailable",
                message: "MyMacCleaner will not permanently delete files."
            )
        case .emptyTrash:
            presentation(
                title: "Empty Trash is unavailable",
                message: "MyMacCleaner will not empty Trash automatically."
            )
        case .privilegedMaintenance:
            presentation(
                title: "Privileged maintenance is unavailable",
                message: "MyMacCleaner will not request administrator access for maintenance."
            )
        case .memoryPurge:
            presentation(
                title: "Memory purge is unavailable",
                message: "MyMacCleaner provides memory guidance without purging memory."
            )
        case .processTermination:
            presentation(
                title: "Process termination is unavailable",
                message: "MyMacCleaner will not terminate processes."
            )
        case .startupItemMutation:
            presentation(
                title: "Startup changes are unavailable",
                message: "MyMacCleaner will not change startup items."
            )
        case .developerToolMutation:
            presentation(
                title: "Developer tool changes are unavailable",
                message: "MyMacCleaner will not change developer tools."
            )
        case .systemSettingsMutation:
            presentation(
                title: "System setting changes are unavailable",
                message: "MyMacCleaner will not change system settings."
            )
        case .legacyCleanup:
            presentation(
                title: "Legacy cleanup is unavailable",
                message: "MyMacCleaner requires a reviewed cleanup plan before changing files."
            )
        case .reviewedPlanCleanup:
            presentation(
                title: "Reviewed cleanup plans are coming later",
                message: "MyMacCleaner will offer reviewed cleanup plans after the safety pipeline is ready."
            )
        }
    }

    private static func presentation(title: String, message: String) -> Self {
        Self(
            tone: .informational,
            title: title,
            message: message,
            actionTitle: "Learn why"
        )
    }
}
