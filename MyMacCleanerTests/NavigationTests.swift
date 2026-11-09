import Testing
import Foundation
import SwiftUI
@testable import MyMacCleaner

// MARK: - Navigation Section Tests

@Suite("Navigation Section Tests")
struct NavigationSectionTests {

    @Test("All navigation sections are defined")
    func allSectionsExist() async throws {
        let sections = NavigationSection.allCases
        #expect(sections.count == 12)
        #expect(sections.contains(.home))
        #expect(sections.contains(.adaptiveExperience))
        #expect(sections.contains(.diskCleaner))
        #expect(sections.contains(.spaceLens))
        #expect(sections.contains(.orphanedFiles))
        #expect(sections.contains(.duplicates))
        #expect(sections.contains(.performance))
        #expect(sections.contains(.applications))
        #expect(sections.contains(.startupItems))
        #expect(sections.contains(.portManagement))
        #expect(sections.contains(.systemHealth))
        #expect(sections.contains(.permissions))
    }

    @Test("Each section has a unique raw value")
    func uniqueRawValues() async throws {
        let rawValues = NavigationSection.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }

    @Test("The Go menu gives the first nine sections Command-1 to Command-9, in sidebar order")
    func goMenuShortcuts() {
        #expect(NavigationSection.home.goShortcut == KeyboardShortcut("1"))
        #expect(NavigationSection.adaptiveExperience.goShortcut == KeyboardShortcut("2"))
        #expect(NavigationSection.startupItems.goShortcut == KeyboardShortcut("9"))
        #expect(NavigationSection.portManagement.goShortcut == nil)
        #expect(NavigationSection.allCases.compactMap(\.goShortcut).count == 9)
    }
}
