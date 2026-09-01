import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window: small tabs, no giant preferences surface.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let store: LocationsStore

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            timeTab.tabItem { Label("Time", systemImage: "clock") }
            appearanceTab.tabItem { Label("Appearance", systemImage: "sparkles") }
            locationsTab.tabItem { Label("Locations", systemImage: "list.bullet") }
            advancedTab.tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 440)
        .padding(.bottom, 12)
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            LaunchAtLoginToggle()
            KeyboardShortcuts.Recorder("Toggle Panel:", name: .togglePanel)
            LabeledContent("Home:", value: store.home?.cityName ?? "—")
            Toggle("Automatically update Home location", isOn: $settings.autoUpdateHome)
                .disabled(true)
                .help("Coming soon — will ask for location permission when enabled.")
            Picker("Menu bar shows:", selection: $settings.menuBarLocationID) {
                Text("Icon only").tag(String?.none)
                ForEach(store.locations) { location in
                    Text("\(location.cityName) time").tag(String?.some(location.id))
                }
            }
        }
        .padding(20)
    }

    // MARK: Time

    private var timeTab: some View {
        Form {
            Picker("Offset Mode:", selection: $settings.offsetMode) {
                Text("Relative Mode").tag(OffsetMode.relative)
                Text("UTC Mode").tag(OffsetMode.utc)
            }
            .pickerStyle(.radioGroup)

            Picker("Time Format:", selection: $settings.clockFormatPreference) {
                Text("System").tag(ClockFormatPreference.system)
                Text("12-hour").tag(ClockFormatPreference.twelveHour)
                Text("24-hour").tag(ClockFormatPreference.twentyFourHour)
            }
            .pickerStyle(.radioGroup)

            Picker("First day of week:", selection: $settings.firstDayOfWeek) {
                Text("System").tag(FirstDayOfWeek.system)
                Text("Monday").tag(FirstDayOfWeek.monday)
                Text("Sunday").tag(FirstDayOfWeek.sunday)
            }
        }
        .padding(20)
    }

    // MARK: Appearance

    private var appearanceTab: some View {
        Form {
            Toggle("Show weather", isOn: $settings.showWeather)
            Toggle("Show greetings", isOn: $settings.showGreetings)
            Toggle("Show moon phase", isOn: $settings.showMoonPhase)
            Toggle("Animations", isOn: $settings.animationsEnabled)
        }
        .padding(20)
    }

    // MARK: Locations

    private var locationsTab: some View {
        VStack(spacing: 8) {
            Text("Locations are managed in the Panel.")
            Text("Personal labels (\u{201C}Sarah\u{201D}, \u{201C}Techzy SF\u{201D}) arrive in a later release.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(30)
    }

    // MARK: Advanced

    @State private var confirmingReset = false

    private var advancedTab: some View {
        Form {
            LabeledContent("Configuration:") {
                HStack {
                    Button("Export…") { exportConfiguration() }
                    Button("Import…") { importConfiguration() }
                }
            }
            LabeledContent("Data:") {
                Button("Reset All Data…", role: .destructive) { confirmingReset = true }
            }
        }
        .padding(20)
        .confirmationDialog(
            "Reset all data?",
            isPresented: $confirmingReset
        ) {
            Button("Reset", role: .destructive) {
                store.resetToSeed()
                settings.restore(
                    SettingsSnapshot(
                        offsetMode: .relative, clockFormatPreference: .system,
                        showWeather: true, showGreetings: true, showMoonPhase: true,
                        animationsEnabled: true, firstDayOfWeek: .system,
                        autoUpdateHome: false, menuBarLocationID: nil
                    )
                )
            }
        } message: {
            Text("Locations return to the defaults and every preference resets.")
        }
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "WorldClock Configuration.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let file = ConfigurationFile(locations: store.locations, settings: settings.snapshot)
        try? file.encoded().write(to: url)
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let file = try? ConfigurationFile(decoding: data)
        else { return }
        store.replaceAll(with: file.locations)
        settings.restore(file.settings)
    }

    // MARK: About

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Text("WorldClock")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
                .font(.callout)
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 6) {
                Text("Released under the MIT License.")
                Text("City data from GeoNames (geonames.org), licensed CC-BY 4.0.")
                Text("Earth imagery: NASA Earth Observatory (Blue Marble, Black Marble).")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }
}

/// SMAppService-backed launch-at-login toggle; state reads from the service.
private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $isEnabled)
            .onChange(of: isEnabled) {
                do {
                    if isEnabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Registration can fail (e.g. unsigned dev builds);
                    // reflect reality rather than pretending.
                    isEnabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
