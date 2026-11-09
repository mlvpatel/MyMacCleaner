import SwiftUI
import CleanerCore

struct AdaptiveExperienceView: View {
    @ObservedObject var viewModel: AdaptiveExperienceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ExperienceDashboardView(viewModel: viewModel)
            .accessibilityIdentifier("adaptive.dashboard")
            .overlay {
                ToastOverlay(presenter: viewModel.toasts)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(L("adaptive.mode.title"), selection: modeBinding) {
                        Text(L("adaptive.mode.guided"))
                            .tag(CleanerCore.PresentationMode.guided)
                            .accessibilityIdentifier("adaptive.mode.guided")
                        Text(L("adaptive.mode.standard"))
                            .tag(CleanerCore.PresentationMode.standard)
                            .accessibilityIdentifier("adaptive.mode.standard")
                        Text(L("adaptive.mode.technical"))
                            .tag(CleanerCore.PresentationMode.technical)
                            .accessibilityIdentifier("adaptive.mode.technical")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("adaptive.mode.picker")
                    .accessibilityHint(L("adaptive.mode.hint"))
                    .disabled(viewModel.isRefreshing)
                }
                ToolbarItem(placement: .primaryAction) {
                    // Stop stays reachable after the review sheet is closed.
                    if viewModel.isExecuting {
                        Button(L("adaptive.execution.stop")) {
                            viewModel.dispatch(.cancel)
                        }
                        .accessibilityIdentifier("adaptive.toolbar.execution.stop")
                        .accessibilityHint(L("adaptive.execution.stop.hint"))
                        .keyboardShortcut(".", modifiers: .command)
                        .disabled(viewModel.isStopRequested)
                    } else if viewModel.isRefreshing {
                        Button(L("adaptive.scan.stop")) {
                            viewModel.dispatch(.cancel)
                        }
                        .accessibilityIdentifier("adaptive.scan.stop")
                        .accessibilityHint(L("adaptive.scan.stop.hint"))
                        .keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button(L("adaptive.refresh")) {
                            viewModel.dispatch(.refresh)
                        }
                        .accessibilityIdentifier("adaptive.evidence.refresh")
                        .accessibilityHint(L("adaptive.refresh.hint"))
                        .keyboardShortcut("r", modifiers: .command)
                        .help(L("adaptive.refresh.hint"))
                    }
                }
            }
            .sheet(item: sheetBinding) { sheet in
                sheetView(sheet)
            }
            .animation(reduceMotion ? nil : Theme.Animation.spring, value: viewModel.snapshot?.mode)
            .onAppear {
                viewModel.pageAppeared()
            }
            .onDisappear {
                viewModel.pageDisappeared()
            }
            .onChange(of: viewModel.showOnboarding) { _, isShowing in
                // The first load waits for onboarding, then runs as the sheet closes.
                if !isShowing {
                    viewModel.pageAppeared()
                }
            }
    }

    private var modeBinding: Binding<CleanerCore.PresentationMode> {
        Binding(
            get: { viewModel.presentationMode },
            set: { viewModel.setMode($0) }
        )
    }

    private var sheetBinding: Binding<AdaptiveSheet?> {
        Binding(
            get: { viewModel.sheet },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissSheet()
                }
            }
        )
    }

    @ViewBuilder
    private func sheetView(_ sheet: AdaptiveSheet) -> some View {
        switch sheet {
        case .onboarding:
            AdaptiveOnboardingView {
                viewModel.dispatch(.acknowledgeOnboarding)
            }
        case .review:
            ReviewEvidenceView(viewModel: viewModel)
        case .receipts:
            ReceiptRecoveryView(viewModel: viewModel)
        case .permissionHelp:
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ProtectedDataNotice(
                    titleKey: "adaptive.permission.title",
                    messageKey: "adaptive.permission.body"
                )
                .accessibilityIdentifier("adaptive.warning.permission")
                HStack(spacing: Theme.Spacing.sm) {
                    // Full Disk Access covers both gaps: the protected folders and the user Library.
                    Button(L("adaptive.permission.openSettings")) {
                        PermissionsService.shared.openFullDiskAccessSettings()
                        viewModel.dismissSheet()
                    }
                    .accessibilityIdentifier("adaptive.permission.openSettings")
                    .accessibilityHint(L("adaptive.permission.openSettings.hint"))
                    .keyboardShortcut(.defaultAction)
                    Button(L("adaptive.permission.close")) {
                        viewModel.dismissSheet()
                    }
                    .accessibilityIdentifier("adaptive.permission.close")
                    .accessibilityHint(L("adaptive.permission.close.hint"))
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(minWidth: 420)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("adaptive.permission.sheet")
        }
    }
}

extension AdaptiveSheet: Identifiable {
    var id: String {
        switch self {
        case .onboarding: return "adaptive.sheet.onboarding"
        case .review: return "adaptive.sheet.review"
        case .receipts: return "adaptive.sheet.receipts"
        case .permissionHelp: return "adaptive.sheet.permission"
        }
    }
}

struct AdaptiveOnboardingView: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(L("adaptive.onboarding.title"))
                .font(Theme.Typography.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("adaptive.onboarding.title")
            Text(L("adaptive.onboarding.offline"))
            Text(L("adaptive.onboarding.noLogin"))
            Text(L("adaptive.onboarding.staysLocal"))
            Text(L("adaptive.onboarding.noScan"))
            Text(L("adaptive.onboarding.learn-evidence"))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("adaptive.onboarding.learn-evidence")
            Button(L("adaptive.onboarding.continue")) {
                onAcknowledge()
            }
            .accessibilityIdentifier("adaptive.onboarding.continue")
            .accessibilityHint(L("adaptive.onboarding.continue.hint"))
            .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 480, minHeight: 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adaptive.onboarding.sheet")
    }
}
