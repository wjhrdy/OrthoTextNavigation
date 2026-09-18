#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["python-rtmidi>=1.5.8"]
# ///
"""Set the Teenage Engineering Ortho Remote to relative or absolute mode.

Ported from https://github.com/evnoj/ortho-remote-relative-mode.
The SysEx commands follow the OR1 specification documented there.
"""

import argparse

import rtmidi


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--midi-name", required=True, help="MIDI output port name")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--relative", action="store_true", help="enable relative mode")
    mode.add_argument("--absolute", action="store_true", help="enable absolute mode")
    args = parser.parse_args()

    midi_out = rtmidi.MidiOut()
    ports = midi_out.get_ports()
    if args.midi_name not in ports:
        parser.error(f"MIDI port not found: {args.midi_name!r}. Available ports: {ports or 'none'}")

    setting = 0x00 if args.relative else 0x01
    label = "relative" if args.relative else "absolute"
    message = [0xF0, 0x00, 0x20, 0x76, 0x02, 0x00, 0x02, setting, 0xF7]

    try:
        midi_out.open_port(ports.index(args.midi_name))
        print(f"Port opened successfully: {args.midi_name!r}")
        print(f"Sending SysEx to enable {label} mode")
        midi_out.send_message(message)
    finally:
        midi_out.close_port()
        print(f"Port closed: {args.midi_name!r}")


if __name__ == "__main__":
    main()
