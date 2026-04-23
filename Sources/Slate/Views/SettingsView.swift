import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.themeID) {
                    ForEach(SlateTheme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }

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
                Text("Block mode is intentionally out of service in this stabilization build while Classic terminal basics are hardened.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 12)
    }
}
