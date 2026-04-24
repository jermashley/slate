import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Appearance") {
                Text("Slate follows the system light and dark appearance.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                TextField("Font", text: $settings.fontName)

                HStack {
                    Slider(value: $settings.fontSize, in: 10...22, step: 0.5)
                    Text(settings.fontSize, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                Picker("Cursor", selection: Binding(
                    get: { settings.cursorStyle },
                    set: { settings.cursorStyle = $0 }
                )) {
                    ForEach(CursorStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }

            Section("Session") {
                Picker("Default mode", selection: Binding(
                    get: { settings.sessionStyle },
                    set: { settings.sessionStyle = $0 }
                )) {
                    ForEach(SessionStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                TextField("Shell override", text: $settings.shellOverride, prompt: Text(settings.resolvedShell))
                TextField("Startup directory", text: $settings.startupDirectory, prompt: Text("Home folder"))

                HStack {
                    Stepper("Scrollback", value: $settings.scrollbackLimit, in: 1_000...50_000, step: 1_000)
                    Text("\(settings.scrollbackLimit.formatted()) lines")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Text("Slate has no accounts, cloud sync, AI features, or behavioral telemetry in this build.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                Text("Block Mode is the default for new tabs. It currently supports zsh, saves command metadata locally, and keeps Classic available for compatibility.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 12)
    }
}
