import SwiftUI

@main
struct MyMacCleanerApp: App {
    /// Asks before Quit ends a Trash run.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Shared app state that persists across section switches
    @StateObject private var appState = AppState()

    /// Menu bar controller
    @StateObject private var menuBarController = MenuBarController.shared

    /// Menu bar visibility setting
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    init() {
        // The app is English-only; drop the retired language preference
        UserDefaults.standard.removeObject(forKey: Self.retiredLanguagePreferenceKey)
        // Load saved display mode
        MenuBarController.shared.loadSavedDisplayMode()
    }

    private static let retiredLanguagePreferenceKey = "appLanguage"

    /// SwiftUI names WindowGroup windows "...-AppWindow-<n>"; Settings and the menu bar popover
    /// are named differently, and a closed window is no longer visible.
    static func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible || window.isMiniaturized else { return false }
        return window.identifier?.rawValue.contains("-AppWindow-") == true
    }

    /// Opens a new main window through File > New Window (Command-N), the command SwiftUI
    /// installs for the WindowGroup, exactly as if the user chose it. The WindowGroup deliberately
    /// has no id, so `openWindow(id:)` is not used: with an id, SwiftUI restored a saved state with
    /// no windows at launch and the app started without any window (the UI tests caught it).
    @MainActor static func reopenMainWindow() {
        for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            if let index = menu.items.firstIndex(where: isNewWindowItem) {
                menu.performActionForItem(at: index)
                return
            }
        }
    }

    private static func isNewWindowItem(_ item: NSMenuItem) -> Bool {
        item.keyEquivalent == "n" && item.keyEquivalentModifierMask == .command
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appDelegate.attach(appState.adaptiveExperienceViewModel)
                    // Setup menu bar if enabled
                    if showInMenuBar {
                        menuBarController.setup()
                    }
                }
                .onChange(of: showInMenuBar) { _, newValue in
                    if newValue {
                        menuBarController.setup()
                    } else {
                        menuBarController.teardown()
                    }
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            GoCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(menuBarController)
        }
        #endif
    }
}

/// Go menu: every section, Command-1 to Command-9 for the first nine, in the key window.
struct GoCommands: Commands {
    @FocusedBinding(\.selectedSection) private var selectedSection

    var body: some Commands {
        CommandMenu(L("navigation.menu.go")) {
            ForEach(NavigationSection.allCases) { section in
                Button(section.localizedName) {
                    selectedSection = section
                }
                .keyboardShortcut(section.goShortcut)
                .disabled(selectedSection == nil)
            }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(L("settings.general"), systemImage: "gear")
                }

            UpdateSettingsView()
                .tabItem {
                    Label(L("settings.updates"), systemImage: "arrow.triangle.2.circlepath")
                }

            PermissionsSettingsView()
                .tabItem {
                    Label(L("settings.permissions"), systemImage: "lock.shield")
                }

            AboutSettingsView()
                .tabItem {
                    Label(L("settings.about"), systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 320)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @EnvironmentObject var menuBarController: MenuBarController

    var body: some View {
        Form {
            Section {
                Toggle(L("settings.showInMenuBar"), isOn: $showInMenuBar)

                if showInMenuBar {
                    Picker(L("settings.menuBarDisplay"), selection: Binding(
                        get: { menuBarController.displayMode },
                        set: { menuBarController.setDisplayMode($0) }
                    )) {
                        ForEach(MenuBarController.DisplayMode.allCases, id: \.rawValue) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(L("settings.menuBarDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

struct UpdateSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            UpdateCapabilityView(capability: .current)
            Spacer()
        }
        .padding()
    }
}

struct PermissionsSettingsView: View {
    @ObservedObject private var permissionsService = PermissionsService.shared

    var body: some View {
        let hasAccess = permissionsService.hasFullDiskAccess
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(L("settings.permissions"))
                .font(.headline)

            HStack {
                Image(systemName: hasAccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(hasAccess ? .green : .orange)
                    .accessibilityHidden(true)
                Text(L("settings.fullDiskAccess"))
                Text(L(hasAccess ? "settings.fullDiskAccess.granted" : "settings.fullDiskAccess.notGranted"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("settings.openSettings")) {
                    openSystemPreferences()
                }
            }

            Text(L("settings.fdaDescription"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .onAppear { permissionsService.checkFullDiskAccess() }
        // Picks up a change made in System Settings while this window was open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionsService.checkFullDiskAccess()
        }
    }

    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

struct AboutSettingsView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(Theme.Typography.size48)
                .foregroundStyle(.blue.gradient)

            Text("MyMacCleaner")
                .font(.title.bold())

            Text(LFormat("settings.version %@", appVersion))
                .foregroundStyle(.secondary)

            Text(L("settings.aboutDescription"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }
}
