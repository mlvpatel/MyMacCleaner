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

    func homeTrashReviewNotice() -> SafetyNoticeState {
        notice(for: .homeEmptyTrash)
    }

    func diskTrashReviewNotice() -> SafetyNoticeState {
        notice(for: .diskEmptyTrash)
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
    case homeEmptyTrash = "home.empty-trash"
    case diskEmptyTrash = "disk.empty-trash"

    var operation: UnsupportedOperation {
        switch self {
        case .homeEmptyTrash, .diskEmptyTrash:
            .emptyTrash
        }
    }
}
