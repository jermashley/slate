# Slate

Slate is a native macOS terminal for everyday developers: minimal, refined, local-first, and built for dependable daily use.

This repository currently contains a SwiftTerm-backed stabilization build with Classic terminal basics plus an early Block Mode:

- SwiftUI/AppKit macOS app shell
- SwiftTerm-backed PTY terminal sessions
- tabs
- visible close control for active and hovered tabs
- curated themes
- settings for font, shell, startup directory, scrollback, and cursor
- built-in SwiftTerm find bar via `Cmd-F`
- Block Mode as the default new-tab experience for zsh, with native command composition and local command metadata persistence
- Classic Mode as a compatibility fallback for unsupported shells and raw terminal workflows
- privacy-first posture with no accounts, cloud sync, AI, or behavioral telemetry

## Build

```sh
swift build
```

## Package As App

```sh
zsh Scripts/package_app.sh --rebuild
```

This creates:

```text
dist/Slate.app
```

It also copies Swift package resource bundles into the app so it is self-contained for testing on another Mac.

## Export Test Build

```sh
zsh Scripts/export_test_build.sh --rebuild
```

This creates:

```text
dist/Slate-mac-test.zip
```

That zip is the handoff artifact to move to another machine.

On this machine, the most reliable launch path is:

```sh
zsh Scripts/run_app.sh
```

To rebuild first:

```sh
zsh Scripts/run_app.sh --rebuild
```

`Scripts/run_app.sh` launches the current built binary directly, which avoids stale packaged-app launches and the Launch Services issues in this Command Line Tools-only environment. `open dist/Slate.app` should work on a normal macOS setup.

## Testing On Another Mac

- Send `dist/Slate-mac-test.zip`
- Unzip it on the other machine
- Open `Slate.app`
- If macOS warns because the app is not Developer ID signed/notarized yet, use right-click -> `Open`

## Notes

Block Mode is the default for new tabs and currently supports zsh first. Command metadata is saved locally; command output is session-only and is not restored after relaunch.
