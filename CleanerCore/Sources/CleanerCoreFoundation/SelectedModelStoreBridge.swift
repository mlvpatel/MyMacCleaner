import CleanerCore
import Foundation

/// A directory the user explicitly chose to inventory (e.g. via a system open
/// panel), paired with the read-only selected root the scan will observe.
public struct SelectedModelStoreSelection: Sendable {
    public let root: ModelStoreRoot
    public let rootID: DeclaredRootID
    public let directory: URL
}

/// The sanctioned, app-mediated way to widen a model-store scan to a directory
/// the user explicitly picked.
///
/// Scope never widens silently: the core scan pipeline discovers no selected
/// roots on its own (`SelectedRootInventoryDetector` yields nothing), and this
/// bridge is the only issuer of a *validated* selected root. Callers must invoke
/// it only in response to a genuine user selection — that user consent is what
/// the returned root's validated authority records. The resulting root is still
/// inventory-only; the selected-root parser reads structure, never contents, and
/// never mutates.
public enum SelectedModelStoreBridge {
    public static func makeSelection(
        forUserChosenDirectory directory: URL,
        layout: ModelStoreLayoutVersion = .selectedRootV1
    ) -> SelectedModelStoreSelection {
        let rootID = opaqueRootID()
        return SelectedModelStoreSelection(
            root: .explicitlySelected(rootID: rootID, selection: .validated, layout: layout),
            rootID: rootID,
            directory: directory.standardizedFileURL
        )
    }

    /// An opaque, per-selection identifier. It deliberately does not encode the
    /// chosen path, so the identifier can appear in diagnostics without leaking
    /// where the user's models live.
    private static func opaqueRootID() -> DeclaredRootID {
        do {
            return try DeclaredRootID("selected-model-root-" + UUID().uuidString.lowercased())
        } catch {
            preconditionFailure("selected model-store root identifier must be valid")
        }
    }
}
