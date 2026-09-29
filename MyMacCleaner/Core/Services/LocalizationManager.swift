import Foundation

// MARK: - Localization
//
// The app ships English only. Strings live in per-feature String Catalogs
// (MyMacCleaner/Resources/*.xcstrings) and are compiled into en.lproj tables.

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

// MARK: - Localized String Helpers

/// Returns the English string for a catalog key, e.g. L("home.title"): the key's own
/// table, then the Common table, then the key itself. `Bundle` loads and caches the tables.
///
/// IMPORTANT: This takes a plain String, NOT String.LocalizationValue!
/// "\(key)" on a LocalizationValue performs Apple's localization, not key extraction.
func L(_ key: String) -> String {
    let value = Bundle.main.localizedString(forKey: key, value: nil, table: tableForKey(key))
    return value != key ? value : Bundle.main.localizedString(forKey: key, value: key, table: fallbackTable)
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
