import Foundation

struct ReadOnlyInspection {
    func displayName(at url: URL) -> String? {
        try? url.resourceValues(forKeys: [.nameKey]).name
    }
}
