import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Performance Read-Only Tests

@Suite("Performance Read-Only Tests")
struct PerformanceReadOnlyTests {

    @Test("Memory coaching starts unavailable and idle until monitoring begins")
    @MainActor
    func memoryCoachStartsUnavailable() {
        let viewModel = PerformanceViewModel()

        #expect(viewModel.presentation == .unavailable)
        #expect(viewModel.isMonitoring == false)
    }

    @Test("Stopping monitoring leaves the view model idle")
    @MainActor
    func stoppingMonitoringIsIdempotent() {
        let viewModel = PerformanceViewModel()

        viewModel.stopMonitoring()
        viewModel.stopMonitoring()

        #expect(viewModel.isMonitoring == false)
    }

    @Test("Login Items navigation invokes only the injected fixed settings action")
    @MainActor
    func loginItemsNavigationUsesInjectedFixedAction() async throws {
        var invocationCount = 0
        let viewModel = StartupItemsViewModel {
            invocationCount += 1
        }

        viewModel.openLoginItemsSettings()

        #expect(invocationCount == 1)
    }
}
