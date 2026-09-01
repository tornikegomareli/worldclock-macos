import KeyboardShortcuts
import SwiftUI

/// The Settings window: global shortcut, offset interpretation, time format.
struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle Panel:", name: .togglePanel)

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

            Toggle("Show weather", isOn: $settings.showWeather)
            Toggle("Show greetings", isOn: $settings.showGreetings)
        }
        .padding(20)
        .frame(width: 340)
    }
}
