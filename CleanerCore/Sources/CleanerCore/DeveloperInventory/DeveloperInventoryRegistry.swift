public enum DeveloperToolID: String, CaseIterable, Equatable, Sendable {
    case cursor
    case vscode
    case docker
    case homebrew
}

public enum DeveloperPresence: Equatable, Sendable {
    case present
    case absent
    case unavailable
}

public struct DeveloperInventoryRecord: Equatable, Sendable {
    public let tool: DeveloperToolID
    public let presence: DeveloperPresence
    public let protection: CapabilityProtectionReason

    public init(tool: DeveloperToolID, presence: DeveloperPresence) {
        self.tool = tool
        self.presence = presence
        protection = .protectedSemanticOwner
    }

    public var inventoryFact: AdaptiveDeveloperInventoryFact? {
        let identity = "developer.\(tool.rawValue)"
        do {
            return try AdaptiveDeveloperInventoryFact(
                opaqueID: identity,
                presenceKey: "adaptive.developer.\(tool.rawValue).\(presenceMarker)",
                protectionKey: "adaptive.developer.protected"
            )
        } catch {
            return nil
        }
    }

    private var presenceMarker: String {
        switch presence {
        case .present: return "present"
        case .absent: return "absent"
        case .unavailable: return "unavailable"
        }
    }
}

public enum DeveloperInventoryRegistry {
    public static let version = "1.0.0"

    public static func records(presence: [DeveloperToolID: DeveloperPresence]) -> [DeveloperInventoryRecord] {
        DeveloperToolID.allCases.map { tool in
            DeveloperInventoryRecord(tool: tool, presence: presence[tool] ?? .unavailable)
        }
    }

    public static func facts(presence: [DeveloperToolID: DeveloperPresence]) -> [AdaptiveDeveloperInventoryFact] {
        records(presence: presence).compactMap(\.inventoryFact)
    }
}
