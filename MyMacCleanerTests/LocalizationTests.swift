import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Localization Tests

@Suite("Localization Tests")
struct LocalizationTests {

    private static let supportedLocales = ["en"]

    private var resourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MyMacCleaner/Resources")
    }

    @Test("Every string catalog contains only English localizations")
    func catalogsAreEnglishOnly() throws {
        let catalogs = try FileManager.default
            .contentsOfDirectory(at: resourcesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xcstrings" }
        #expect(!catalogs.isEmpty)

        for catalog in catalogs {
            let data = try Data(contentsOf: catalog)
            let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(root["sourceLanguage"] as? String == "en", "\(catalog.lastPathComponent) source language")

            let strings = root["strings"] as? [String: Any] ?? [:]
            for (key, rawEntry) in strings {
                let entry = rawEntry as? [String: Any] ?? [:]
                let localizations = entry["localizations"] as? [String: Any] ?? [:]
                #expect(
                    localizations.keys.sorted() == Self.supportedLocales,
                    "\(catalog.lastPathComponent): \(key) has locales \(localizations.keys.sorted())"
                )
            }
        }
    }

    @Test("Language selection keys are removed")
    func languageSelectionKeysAreRemoved() throws {
        let settings = try String(contentsOf: resourcesDirectory.appendingPathComponent("Settings.xcstrings"))
        #expect(!settings.contains("\"settings.language\""))
        #expect(!settings.contains("\"settings.languageNote\""))
    }

    @Test("Unknown keys fall back to the key itself")
    func unknownKeyReturnsKey() {
        #expect(L("tests.missing.key") == "tests.missing.key")
    }
}
