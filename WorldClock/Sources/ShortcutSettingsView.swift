import KeyboardShortcuts
import SwiftUI

/// The tiny recorder window behind "Set Shortcut…".
struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle Panel:", name: .togglePanel)
        }
        .padding(20)
        .frame(width: 300)
    }
}
