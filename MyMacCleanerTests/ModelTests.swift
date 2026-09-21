import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Scan Category Tests

@Suite("Scan Category Tests")
struct ScanCategoryTests {

    @Test("All scan categories have paths defined")
    func allCategoriesHavePaths() async throws {
        for category in ScanCategory.allCases {
            #expect(!category.paths.isEmpty, "Category \(category.rawValue) should have paths")
        }
    }

    @Test("Categories have localized names")
    func categoriesHaveLocalizedNames() async throws {
        for category in ScanCategory.allCases {
            let name = category.localizedName
            #expect(!name.isEmpty, "Category \(category.rawValue) should have a localized name")
        }
    }

    @Test("Categories have icons defined")
    func categoriesHaveIcons() async throws {
        for category in ScanCategory.allCases {
            let icon = category.icon
            #expect(!icon.isEmpty, "Category \(category.rawValue) should have an icon")
        }
    }

    @Test("FDA requirement is properly set")
    func fdaRequirements() async throws {
        // System cache typically requires FDA
        #expect(ScanCategory.systemCache.requiresFullDiskAccess == true)
        // User cache doesn't require FDA
        #expect(ScanCategory.userCache.requiresFullDiskAccess == false)
    }

    @Test("User consent requirement is properly set for TCC-protected directories")
    func userConsentRequirements() async throws {
        // Downloads and mail attachments require user consent (TCC-protected)
        #expect(ScanCategory.downloads.requiresUserConsent == true)
        #expect(ScanCategory.mailAttachments.requiresUserConsent == true)
        // Other categories don't require explicit user consent
        #expect(ScanCategory.userCache.requiresUserConsent == false)
        #expect(ScanCategory.systemCache.requiresUserConsent == false)
        #expect(ScanCategory.browserCache.requiresUserConsent == false)
    }
}

// MARK: - Cleanable Item Tests

@Suite("Cleanable Item Tests")
struct CleanableItemTests {

    @Test("Item is selected by default")
    func itemSelectedByDefault() async throws {
        let item = CleanableItem(
            name: "test.txt",
            path: URL(fileURLWithPath: "/tmp/test.txt"),
            size: 1024,
            modificationDate: Date(),
            category: .userCache
        )
        #expect(item.isSelected == true)
    }

    @Test("Item has unique ID")
    func itemHasUniqueId() async throws {
        let item1 = CleanableItem(
            name: "test1.txt",
            path: URL(fileURLWithPath: "/tmp/test1.txt"),
            size: 1024,
            modificationDate: Date(),
            category: .userCache
        )
        let item2 = CleanableItem(
            name: "test2.txt",
            path: URL(fileURLWithPath: "/tmp/test2.txt"),
            size: 1024,
            modificationDate: Date(),
            category: .userCache
        )
        #expect(item1.id != item2.id)
    }
}

// MARK: - Scan Result Tests

@Suite("Scan Result Tests")
struct ScanResultTests {

    @Test("Total size is calculated correctly")
    func totalSizeCalculation() async throws {
        var items = [
            CleanableItem(
                name: "file1.txt",
                path: URL(fileURLWithPath: "/tmp/file1.txt"),
                size: 1000,
                modificationDate: Date(),
                category: .userCache
            ),
            CleanableItem(
                name: "file2.txt",
                path: URL(fileURLWithPath: "/tmp/file2.txt"),
                size: 2000,
                modificationDate: Date(),
                category: .userCache
            )
        ]

        let result = ScanResult(category: .userCache, items: items)
        #expect(result.totalSize == 3000)
    }

    @Test("Selected size only counts selected items")
    func selectedSizeCalculation() async throws {
        var item1 = CleanableItem(
            name: "file1.txt",
            path: URL(fileURLWithPath: "/tmp/file1.txt"),
            size: 1000,
            modificationDate: Date(),
            category: .userCache
        )
        var item2 = CleanableItem(
            name: "file2.txt",
            path: URL(fileURLWithPath: "/tmp/file2.txt"),
            size: 2000,
            modificationDate: Date(),
            category: .userCache
        )
        item2.isSelected = false

        var result = ScanResult(category: .userCache, items: [item1, item2])
        #expect(result.selectedSize == 1000)
    }

    @Test("Item count is correct")
    func itemCountIsCorrect() async throws {
        let items = (1...5).map { i in
            CleanableItem(
                name: "file\(i).txt",
                path: URL(fileURLWithPath: "/tmp/file\(i).txt"),
                size: Int64(i * 100),
                modificationDate: Date(),
                category: .userCache
            )
        }

        let result = ScanResult(category: .userCache, items: items)
        #expect(result.itemCount == 5)
    }
}

// MARK: - Toast Type Tests

@Suite("Toast Type Tests")
struct ToastTypeTests {

    @Test("Toast types have icons")
    func toastTypesHaveIcons() async throws {
        #expect(!ToastType.success.icon.isEmpty)
        #expect(!ToastType.error.icon.isEmpty)
        #expect(!ToastType.info.icon.isEmpty)
    }

    @Test("Toast types have distinct icons")
    func toastTypesHaveDistinctIcons() async throws {
        let icons = [ToastType.success.icon, ToastType.error.icon, ToastType.info.icon]
        let uniqueIcons = Set(icons)
        #expect(icons.count == uniqueIcons.count)
    }
}

// MARK: - Theme Tests

@Suite("Theme Tests")
struct ThemeTests {

    @Test("Spacing values are positive")
    func spacingValuesPositive() async throws {
        #expect(Theme.Spacing.xxs > 0)
        #expect(Theme.Spacing.xs > 0)
        #expect(Theme.Spacing.sm > 0)
        #expect(Theme.Spacing.md > 0)
        #expect(Theme.Spacing.lg > 0)
        #expect(Theme.Spacing.xl > 0)
        #expect(Theme.Spacing.xxl > 0)
    }

    @Test("Spacing values are in ascending order")
    func spacingValuesAscending() async throws {
        #expect(Theme.Spacing.xxs < Theme.Spacing.xs)
        #expect(Theme.Spacing.xs < Theme.Spacing.sm)
        #expect(Theme.Spacing.sm < Theme.Spacing.md)
        #expect(Theme.Spacing.md < Theme.Spacing.lg)
        #expect(Theme.Spacing.lg < Theme.Spacing.xl)
        #expect(Theme.Spacing.xl < Theme.Spacing.xxl)
        #expect(Theme.Spacing.xxl < Theme.Spacing.xxxl)
        #expect(Theme.Spacing.xxxl < Theme.Spacing.huge)
        #expect(Theme.Spacing.huge < Theme.Spacing.massive)
    }

    @Test("Corner radius values are positive")
    func cornerRadiusValuesPositive() async throws {
        #expect(Theme.CornerRadius.small > 0)
        #expect(Theme.CornerRadius.medium > 0)
        #expect(Theme.CornerRadius.large > 0)
        #expect(Theme.CornerRadius.xl > 0)
        #expect(Theme.CornerRadius.pill > 0)
    }

    @Test("Thresholds are properly defined")
    func thresholdsAreDefined() async throws {
        #expect(Theme.Thresholds.minimumFileSize > 0)
        #expect(Theme.Thresholds.DiskSpace.warningFreeSpace > Theme.Thresholds.DiskSpace.criticalFreeSpace)
        #expect(Theme.Thresholds.StartupItems.criticalCount > Theme.Thresholds.StartupItems.warningCount)
        #expect(Theme.Thresholds.Memory.criticalUsage > Theme.Thresholds.Memory.warningUsage)
    }

    @Test("Timing values are positive")
    func timingValuesPositive() async throws {
        #expect(Theme.Timing.visualFeedback > 0)
        #expect(Theme.Timing.progressStep > 0)
        #expect(Theme.Timing.shortPause > 0)
        #expect(Theme.Timing.completionDisplay > 0)
        #expect(Theme.Timing.toastDuration > 0)
        #expect(Theme.Timing.clearResultsDelay > 0)
        #expect(Theme.Timing.processRefreshInterval > 0)
    }
}
