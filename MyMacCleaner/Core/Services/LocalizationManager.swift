import Foundation

// MARK: - Localization
//
// The app ships English only. Strings live in per-feature String Catalogs
// (MyMacCleaner/Resources/*.xcstrings) and are compiled into en.lproj tables.

/// Locale code for the only shipped localization.
private let developmentLanguageCode = "en"

/// Table used when a key's own table has no value.
private let fallbackTable = "Common"

// MARK: - Table Mapping

/// Maps key prefixes to their String Catalog table names
private let keyPrefixToTable: [(prefix: String, table: String)] = [
    ("applications.", "Applications"),
    ("category.", "DiskCleaner"),
    ("diskCleaner.", "DiskCleaner"),
    ("duplicates.", "Duplicates"),
    ("home.", "Home"),
    ("menuBar.", "MenuBar"),
    ("navigation.", "Common"),
    ("orphans.", "OrphanedFiles"),
    ("performance.", "Performance"),
    ("permissions.", "Permissions"),
    ("portManagement.", "PortManagement"),
    ("privacy.", "DiskCleaner"),
    ("scanResults.", "Home"),
    ("settings.", "Settings"),
    ("update.", "Settings"),
    ("sidebar.", "Common"),
    ("spaceLens.", "DiskCleaner"),
    ("startupItems.", "StartupItems"),
    ("systemHealth.", "SystemHealth"),
    ("common.", "Common"),
]

/// Determines the table name for a given key based on its prefix
private func tableForKey(_ key: String) -> String {
    keyPrefixToTable.first { key.hasPrefix($0.prefix) }?.table ?? fallbackTable
}

// MARK: - Thread-Safe Localization Cache

/// Loads each compiled strings table once and serves lookups from memory.
private final class LocalizationCache: @unchecked Sendable {
    private var tables: [String: [String: String]] = [:]
    private let lock = NSLock()

    /// Looks up a key in its table, then the Common table, then returns the key itself.
    func lookup(key: String) -> String {
        let table = tableForKey(key)
        if let value = strings(for: table)[key] {
            return value
        }
        if table != fallbackTable, let value = strings(for: fallbackTable)[key] {
            return value
        }
        return key
    }

    private func strings(for table: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = tables[table] {
            return cached
        }
        let loaded = Self.loadFromDisk(table: table)
        tables[table] = loaded
        return loaded
    }

    /// Reads `<table>.strings` from the English lproj; missing tables yield an empty dictionary.
    private static func loadFromDisk(table: String) -> [String: String] {
        guard let lprojPath = Bundle.main.path(forResource: developmentLanguageCode, ofType: "lproj") else {
            return [:]
        }
        let stringsURL = URL(fileURLWithPath: lprojPath).appendingPathComponent("\(table).strings")

        // PropertyListSerialization handles the UTF-16 encoding of compiled .strings files
        guard let data = try? Data(contentsOf: stringsURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: String] else {
            return [:]
        }
        return dict
    }
}

/// Shared localization cache instance
private let localizationCache = LocalizationCache()

// MARK: - Localized String Helpers

/// Returns the English string for a catalog key, e.g. L("home.title").
///
/// IMPORTANT: This takes a plain String, NOT String.LocalizationValue!
/// "\(key)" on a LocalizationValue performs Apple's localization, not key extraction.
func L(_ key: String) -> String {
    localizationCache.lookup(key: key)
}

/// Alias for code using L(key:)
func L(key: String) -> String {
    L(key)
}

/// Helper function for format strings with arguments
/// Example: LFormat("diskCleaner.itemsFound %lld", count)
/// The key in String Catalog should include the format specifier
func LFormat(_ keyPattern: String, _ args: CVarArg...) -> String {
    String(format: L(keyPattern), arguments: args)
}
