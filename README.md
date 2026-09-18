# Ortho Text Navigation

Use the knob on a Teenage Engineering Ortho Remote to move through text in macOS. Turn to move the cursor, hold modifier keys to select text or move by word, and use Command mode to select text for deletion.

This is a [BetterTouchTool](https://folivora.ai/) custom action plugin for macOS.

## Requirements

- macOS
- BetterTouchTool with Swift action plugin support
- A Teenage Engineering Ortho Remote connected as a Bluetooth MIDI device
- [`uv`](https://docs.astral.sh/uv/getting-started/installation/)
- Apple Command Line Developer Tools: `xcode-select --install`

## Setup

### 1. Put the Ortho Remote in relative mode

Relative mode makes the knob endless instead of stopping at its minimum and maximum values. With the remote connected, run:

```sh
uv run ortho_remote_relative_mode.py \
  --midi-name="ortho remote Bluetooth" \
  --relative
```

The script installs its only dependency automatically. If your MIDI device has a different name, replace `ortho remote Bluetooth` with that name. Use `--absolute` to restore the remote’s default mode.

The mode-setting script is based on [evnoj/ortho-remote-relative-mode](https://github.com/evnoj/ortho-remote-relative-mode).

### 2. Install the BetterTouchTool plugin

Copy `OrthoTextNavigation.swift` to:

```text
~/Library/Application Support/BetterTouchTool/Plugins/
```

BetterTouchTool will compile and load the plugin. Grant Accessibility permission if macOS requests it, then confirm **Ortho Text Navigation** appears under **Custom Plugin Actions**.

### 3. Add the MIDI controls

Download [`OrthoTextNavigation.bttpreset`](https://github.com/wjhrdy/OrthoTextNavigation/blob/main/OrthoTextNavigation.bttpreset), then in BetterTouchTool choose **Presets → Import Preset** and select the downloaded file. The preset assigns the three MIDI controls to the plugin operations automatically.

The `btt://` one-click import link is not available in the Setapp build of BetterTouchTool because that build does not register the URL scheme. If you use the Setapp build, use the download-and-import steps above. You can also import `OrthoNavigation.json` with BetterTouchTool’s AI Config Assistant, or create the three MIDI triggers manually and assign these plugin operations:

| Control | Operation |
| --- | --- |
| Turn clockwise | Right |
| Turn counter-clockwise | Left |
| Press the knob | Cancel |

Select the Ortho Remote as the MIDI device and re-learn the controls if BetterTouchTool does not recognize the included MIDI values.

## Controls

| Input | Action |
| --- | --- |
| Turn | Move by character |
| Option + turn | Move by word |
| Shift + turn | Extend selection by character |
| Option + Shift + turn | Extend selection by word |
| Command + turn | Select text for deletion when Command is released |
| Option + Command + turn | Select text by word for deletion when Command is released |
| Cancel | Disarm deletion and restore the starting cursor or selection when possible |

## Safety and compatibility

Test with disposable text first. Command mode deletes the selected text when Command is released; press Cancel before releasing Command to disarm it.

The plugin works best in macOS applications that expose an editable Accessibility text field. Unsupported fields fall back to ordinary Left/Right keyboard events. Changing focus, text, selection, or app can cancel a pending deletion.

Secure fields and terminal editors such as Vim and Emacs use fallback keyboard behavior rather than the plugin’s special selection and deletion support.

## Files

- `OrthoTextNavigation.swift` — BetterTouchTool source plugin.
- `OrthoTextNavigation.bttpreset` — BetterTouchTool preset for the three MIDI controls.
- `OrthoNavigation.json` — MIDI trigger configuration.
- `ortho_remote_relative_mode.py` — self-contained `uv` setup script for relative mode.
