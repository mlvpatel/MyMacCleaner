import SwiftUI

@main
struct MyMacCleanerApp: App {
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
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

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(menuBarController)
        }
        #endif
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
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @EnvironmentObject var menuBarController: MenuBarController

    var body: some View {
        Form {
            Toggle(L("settings.launchAtLogin"), isOn: $launchAtLogin)

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
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(L("settings.permissions"))
                .font(.headline)

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(L("settings.fullDiskAccess"))
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
