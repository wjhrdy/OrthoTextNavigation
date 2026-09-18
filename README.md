# Ortho Text Navigation for BetterTouchTool

A Swift action plugin and three MIDI bindings for an Ortho remote. Navigate and select text using the knob, with guarded deletion and cancellation in compatible macOS text fields.

## Files

- `OrthoTextNavigation.swift`: unmodified copy of the installed plugin source.
- `OrthoNavigation.json`: active Right, Left, and Cancel bindings; disabled legacy actions and local record IDs removed.
- `.gitignore`: excludes macOS metadata, compiled plugins, and common local secrets/backups.

## Requirements and installation

1. Install BetterTouchTool with Swift action plugin support and Apple Command Line Developer Tools (`xcode-select --install`). Grant BTT Accessibility permission and other input permissions if requested.
2. Review the source, then copy `OrthoTextNavigation.swift` into `~/Library/Application Support/BetterTouchTool/Plugins/`. BTT detects, compiles, and loads source plugins. Follow any compilation prompts.
3. Confirm **Ortho Text Navigation** appears under **Custom Plugin Actions**.
4. Create/select a dedicated Ortho Text Navigation preset. Give `OrthoNavigation.json` to the BTT AI Config Assistant and ask: "Validate and import these three MIDI triggers globally into the selected preset. Preserve their plugin operations and MIDI filters. Do not create duplicates or modify existing triggers."
5. This is a trigger JSON array, NOT a full `.bttpreset` archive; do not simply rename it. Alternatively, create three MIDI triggers manually and assign Ortho Text Navigation actions with operations Right, Left, and Cancel.
6. Select your MIDI device and re-learn the inputs if necessary. The export matches `ortho remote Bluetooth`; MIDI controller/note identity is not guaranteed to round-trip fully through JSON. Preserve direction filters after learning.

## Recorded MIDI bindings

| Operation | Type | Additional configuration | Value filter |
| --- | --- | --- | --- |
| Right | Control Change (5191) | 1 | 1; filter enabled |
| Left | Control Change (5191) | 1 | 127; filter enabled |
| Cancel | Note On (5159) | 60 | No velocity filter |

These values are copied from BTT, not a substitute for MIDI learning. Check knob-button press/release behavior, especially because Cancel has no velocity filter.

## Controls in compatible text fields

| Input | Behavior |
| --- | --- |
| Turn | Move by character |
| Option + turn | Move by word |
| Shift + turn | Extend selection by character |
| Option + Shift + turn | Extend selection by word |
| Command + turn | Select for deletion on Command release |
| Option + Command + turn | Select by word for deletion on Command release |
| Cancel action | Disarm deletion and restore starting cursor/selection if the saved context still matches |

**Command mode deletes text when Command is released. Test with disposable text first. Invoke Cancel before releasing Command to disarm it.**

Rotation uses one movement per two consecutive action calls with matching direction/modifiers. Cancel is immediate. Warnings are logged without the plugin emitting a beep.

## Limitations and safety

- Full behavior requires compatible Accessibility text fields with writable selection. Deletion additionally requires a writable selected-text attribute.
- Focus, text, or selection changes invalidate the saved state. Key, mouse, scroll, and app-activation events can disarm deletion.
- Unsupported fields receive ordinary Left/Right events with Option/Shift preserved. The app decides what those keys mean. Restoration and Command deletion are unavailable in fallback mode.
- No special selection support for cmux, Zsh, Codex CLI, Vim, or Emacs is implemented. Shell configuration is not modified.
- Secure fields are excluded from Accessibility mode, but can still receive fallback arrow keys. This is not a security boundary.

## Verification

The installed source previously compiled and loaded successfully. The packaged JSON was validated by BTT; plugin parameters were checked against the exported actions and source because the validator has no typed schema for them. Fresh-machine installation and live MIDI behavior have not been tested.

Test character/word movement, selection, cancellation, and Command-release deletion using disposable text. Verify changing focus disarms deletion. Test terminal fallback separately.

## Sharing

No shell configuration, credentials, conversation history, or unrelated BTT settings are included. Preserve plugin identifier `com.whardy.ortho.textnavigation` unless updating the bindings too.

Source plugins do not need the notarization required for distributed compiled Xcode bundles. See [BTT distribution documentation](https://docs.folivora.ai/docs/plugins/xcode-bundle-distribution).

No license has been chosen. Add your preferred LICENSE before publishing for reuse.
