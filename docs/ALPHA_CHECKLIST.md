# Slate Private Alpha Checklist

Slate should not be shared as a private alpha until these items are solid.

## Terminal Core

- Verify SwiftTerm integration is stable for ANSI color, truecolor, cursor movement, clearing, wrapping, alternate screen, mouse reporting, and bracketed paste.
- Verify Unicode, wide characters, combining marks, and emoji alignment.
- Verify PTY dimensions track the rendered terminal grid correctly on resize.

## Daily Driver Workflows

- Validate `zsh`, `bash`, and `fish`.
- Validate `git`, package managers, local dev servers, and long-running processes.
- Validate `vim`, `less`, `top`, `htop`, and common TUI apps.
- Confirm large output streams do not freeze the UI.

## MVP UX

- Confirm tabs open, close, and switch reliably.
- Add active-process close confirmation.
- Decide whether multiline paste confirmation belongs in the SwiftTerm-backed baseline or a later pass.
- Harden Block Mode shell integration, command composer behavior, persistence, and raw-terminal islands.

## Release

- Add app icon and bundle metadata.
- Add crash-only reporting decision and disclosure.
- Produce signed manual alpha builds from the packaged `.app`.
