import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// A persistent sidebar keeps every Settings section directly accessible.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let store: LocationsStore
    @Bindable var updates: UpdateService
    @State private var selectedSection: SettingsSection? = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .padding(.vertical, 5)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Settings sections")
            .frame(width: 170)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text((selectedSection ?? .general).rawValue)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                ScrollView {
                    sectionContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(selectedSection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 700, height: 440)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection ?? .general {
        case .general: generalTab
        case .time: timeTab
        case .appearance: appearanceTab
        case .about: aboutTab
        }
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            LaunchAtLoginToggle()
            KeyboardShortcuts.Recorder("Toggle Panel:", name: .togglePanel)
            LabeledContent("Home:", value: store.home?.cityName ?? "—")
            Toggle("Automatically update Home location", isOn: $settings.autoUpdateHome)
                .help("Keeps Home on the nearest city while you travel. If weather is enabled, the city's coordinates are sent to Apple Weather.")
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

    // MARK: About

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Text("WorldClock")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
                .font(.callout)
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(updates.availableVersion.map { "Update to \($0)…" } ?? "Check for Updates…") {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canPresentUpdate)
                    if let date = updates.lastCheckedAt {
                        Text("Checked \(date, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
                    .disabled(!updates.isConfigured)
                Toggle("Notify me when an update is available", isOn: Binding(
                    get: { updates.notificationsEnabled },
                    set: { enabled in Task { await updates.setNotificationsEnabled(enabled) } }
                ))
                .disabled(!updates.isConfigured || updates.requestingNotificationPermission)
                if let message = updates.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case time = "Time"
    case appearance = "Appearance"
    case about = "About"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .time: "clock"
        case .appearance: "sparkles"
        case .about: "info.circle"
        }
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
