public enum DeveloperToolID: String, CaseIterable, Equatable, Sendable {
    // Applications
    case cursor
    case vscode
    case docker
    case zed
    case windsurf
    case chatgpt
    case ollama
    case lmStudio
    case homebrew
    // Dotfile roots under the user's home (sized, content-blind)
    case claudeConfig
    case codex
    case gemini
    case continueConfig
    case cursorConfig
}

public enum DeveloperPresence: Equatable, Sendable {
    case present
    case absent
    case unavailable
}

public struct DeveloperInventoryRecord: Equatable, Sendable {
    public let tool: DeveloperToolID
    public let presence: DeveloperPresence
    /// Content-blind allocated-byte total for a sized root, or nil for a
    /// presence-only tool. Never derived from reading file contents.
    public let sizeBytes: Int?
    public let protection: CapabilityProtectionReason

    public init(tool: DeveloperToolID, presence: DeveloperPresence, sizeBytes: Int? = nil) {
        self.tool = tool
        self.presence = presence
        self.sizeBytes = sizeBytes
        protection = .protectedSemanticOwner
    }

    public var inventoryFact: AdaptiveDeveloperInventoryFact? {
        let identity = "developer.\(tool.rawValue)"
        do {
            return try AdaptiveDeveloperInventoryFact(
                opaqueID: identity,
                presenceKey: "adaptive.developer.\(tool.rawValue).\(presenceMarker)",
                protectionKey: "adaptive.developer.protected",
                sizeBytes: presence == .present ? sizeBytes : nil
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
    public static let version = "1.1.0"

    public static func records(
        presence: [DeveloperToolID: DeveloperPresence],
        sizes: [DeveloperToolID: Int] = [:]
    ) -> [DeveloperInventoryRecord] {
        DeveloperToolID.allCases.map { tool in
            DeveloperInventoryRecord(
                tool: tool,
                presence: presence[tool] ?? .unavailable,
                sizeBytes: sizes[tool]
            )
        }
    }

    public static func facts(
        presence: [DeveloperToolID: DeveloperPresence],
        sizes: [DeveloperToolID: Int] = [:]
    ) -> [AdaptiveDeveloperInventoryFact] {
        records(presence: presence, sizes: sizes).compactMap(\.inventoryFact)
    }
}
