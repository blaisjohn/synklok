# Synklok roadmap

Tester: **Wendell** (M-1620 Pro D owner; previously ran the old Python
"M-1620 Rate Sync" script). Ship one change per build where possible so his
feedback maps to a single behaviour.

## Next build — 1.0.2

- **Automatic updates (Sparkle).** Synklok checks `synklok.app` for new
  versions and installs them in one click, so testers stop reinstalling DMGs
  by hand. 1.0.1 → 1.0.2 is still a manual install; every build after that
  updates itself.
- **Copy diagnostics.** One button in Settings copies version, macOS, device
  status and recent log lines, ready to paste into a message.
- **App icon.** Matches the synklok.app mark (green metronome on zinc-950).
- **Rate in the menu bar.** Optional: show `96k` next to the metronome, with a
  warning icon when the device and MADI input disagree.

## Later — test with Wendell one at a time

Ask before each: *how is your M-1620 clocked (coax MADI, optical MADI, word
clock)?* Synklok currently follows **coax MADI only**.

| Change | What it fixes | What Wendell should try |
|---|---|---|
| Wait for the rate to settle | Switching on a single odd reading while the source is changing rates | Flip Pro Tools between 44.1/48/96 quickly; watch for double switches |
| Ignore MADI when not locked | Acting on a rate the device reports while sync shows "No signal" | Unplug / replug the MADI cable mid-session |
| Choose what to follow | Rigs clocked from optical MADI or word clock | Point it at his actual clock source |
| Manual override in the popover | Wanting a fixed rate without turning sync off | Set 48k by hand, confirm sync stays out of the way |
| Follow the Mac directly (Core Audio) | Polling delay; needing MADI lock before reacting | Change the MADIface rate; time how fast the M-1620 follows |
| Fold in Dante Rate Sync | One app for Pro Tools → Dante → M-1620 | Only if he runs Dante (prototype in `~/Downloads/dante_rate_sync`) |
| Tests for the switching logic | Regressions as the rules above get richer | — (internal) |
