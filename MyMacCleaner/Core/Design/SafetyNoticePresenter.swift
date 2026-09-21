import Foundation
import SafetyContract

struct SafetyNoticeState: Equatable, Sendable {
    let title: String
    let message: String
    let actionTitle: String
    let titleKey: String
    let messageKey: String
    let actionTitleKey: String
    let accessibilityIdentifier: String
    let isDestructive: Bool

    init(
        title: String,
        message: String,
        actionTitle: String,
        titleKey: String,
        messageKey: String,
        actionTitleKey: String,
        accessibilityIdentifier: String,
        isDestructive: Bool = false
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.actionTitleKey = actionTitleKey
        self.accessibilityIdentifier = accessibilityIdentifier
        self.isDestructive = isDestructive
    }
}

struct SafetyNoticePresenter: Sendable {
    private let gateway: DisabledOperationGateway

    init(gateway: DisabledOperationGateway = DisabledOperationGateway()) {
        self.gateway = gateway
    }

    func homeSelectedStorageReviewNotice() -> SafetyNoticeState {
        notice(for: .homeReviewedPlanCleanup)
    }

    func homeTrashReviewNotice() -> SafetyNoticeState {
        notice(for: .homeEmptyTrash)
    }

    func diskSelectedStorageReviewNotice() -> SafetyNoticeState {
        notice(for: .diskReviewedPlanCleanup)
    }

    func diskTrashReviewNotice() -> SafetyNoticeState {
        notice(for: .diskEmptyTrash)
    }

    func browserPrivacyReviewNotice() -> SafetyNoticeState {
        notice(for: .browserLegacyCleanup)
    }

    func duplicatesStorageReviewNotice() -> SafetyNoticeState {
        notice(for: .duplicatesReviewedPlanCleanup)
    }

    func orphanedStorageReviewNotice() -> SafetyNoticeState {
        notice(for: .orphanedReviewedPlanCleanup)
    }

    private func notice(for identity: StorageSafetyNoticeIdentity) -> SafetyNoticeState {
        let result = gateway.request(identity.operation)
        let titleKey = "safety.notice.\(result.operation.rawValue).title"
        let messageKey = "safety.notice.\(result.reason.rawValue).message"
        let actionTitleKey = "safety.notice.action.learnWhy"

        return SafetyNoticeState(
            title: L(titleKey),
            message: L(messageKey),
            actionTitle: L(actionTitleKey),
            titleKey: titleKey,
            messageKey: messageKey,
            actionTitleKey: actionTitleKey,
            accessibilityIdentifier: "safety.notice.\(identity.rawValue)"
        )
    }
}

private enum StorageSafetyNoticeIdentity: String, Sendable {
    case homeReviewedPlanCleanup = "home.reviewed-plan-cleanup"
    case homeEmptyTrash = "home.empty-trash"
    case diskReviewedPlanCleanup = "disk.reviewed-plan-cleanup"
    case diskEmptyTrash = "disk.empty-trash"
    case browserLegacyCleanup = "browser.legacy-cleanup"
    case duplicatesReviewedPlanCleanup = "duplicates.reviewed-plan-cleanup"
    case orphanedReviewedPlanCleanup = "orphaned.reviewed-plan-cleanup"

    var operation: UnsupportedOperation {
        switch self {
        case .homeReviewedPlanCleanup,
             .diskReviewedPlanCleanup,
             .duplicatesReviewedPlanCleanup,
             .orphanedReviewedPlanCleanup:
            .reviewedPlanCleanup
        case .homeEmptyTrash, .diskEmptyTrash:
            .emptyTrash
        case .browserLegacyCleanup:
            .legacyCleanup
        }
    }
}
