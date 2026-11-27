import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Launch Work Tests

/// `AppState` builds every view model at launch, so their initializers must not start work.
@Suite("Launch Work Tests")
@MainActor
struct LaunchWorkTests {
    @Test("Port Management reads no ports until its page first appears")
    func portManagementWaitsForThePage() {
        let viewModel = PortManagementViewModel()

        #expect(viewModel.isLoading == false)

        viewModel.loadIfNeeded()
        #expect(viewModel.isLoading)
        viewModel.cancelRefresh()
    }

    @Test("System Health runs no check until its page first appears")
    func systemHealthWaitsForThePage() {
        let viewModel = SystemHealthViewModel()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.healthChecks.isEmpty)

        viewModel.loadIfNeeded()
        #expect(viewModel.isLoading)
    }

    @Test("Permissions probes no folder until its page appears")
    func permissionsWaitForThePage() async {
        let viewModel = PermissionsViewModel()

        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(viewModel.lastChecked == nil)
        #expect(viewModel.isLoading == false)
    }
}
