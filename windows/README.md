# Synklok for Windows

Windows tray-app port of Synklok. Same behaviour as the macOS app: polls the
M-1620 Pro D's control API twice a second and sets its sample rate to match the
MADI input. Checks synklok.app daily for updates (WinSparkle) and asks before
installing.

| Project / folder | What it is |
|---|---|
| `Synklok.Core` | Device client + sync engine (cross-platform; a port of the Mac `SyncEngine`) |
| `Synklok.Core.Tests` | xUnit tests, including end-to-end against the pretend device |
| `Synklok.Tray` | WinForms system-tray app (`Synklok.exe`); `Updater.cs` wraps WinSparkle |
| `Synklok.MockDevice` | Pretend M-1620 for testing without hardware (`PretendM1620.exe`) |
| `installer/` | NSIS installer script (per-user, no admin) and its welcome artwork |
| `tools/` | Icon, installer-art and acknowledgements generators |

Builds on macOS too (`EnableWindowsTargeting`); the tray app only *runs* on
Windows. Releases: `scripts/release-windows.sh` (see SETUP.md → Windows version).

```bash
# .NET 10 SDK; on John's Mac it lives in ~/.dotnet
dotnet test windows/Synklok.Core.Tests
dotnet build windows/Synklok.Tray -c Release
swift windows/tools/make-icons.swift windows/Synklok.Tray/Assets          # regenerate .ico files
swift windows/tools/make-installer-art.swift windows/installer/welcome.bmp  # installer artwork
```

Version and build number come from `project.yml` (passed in by the release
script as `-p:Version` and `-p:SynklokBuild`); local builds say 1.0.3, build 0.

Installed layout: `%LOCALAPPDATA%\Programs\Synklok\` (Synklok.exe,
WinSparkle.dll, Acknowledgements.txt, uninstaller). Settings:
`%APPDATA%\Synklok\settings.json`. Logs: `%LOCALAPPDATA%\Synklok\Logs`.
WinSparkle's own settings: `HKCU\Software\Synklok\WinSparkle`.

Releases aren't code-signed for now (see SETUP.md → Windows version), so
Windows shows "Windows protected your PC" on first install; updates are still
verified with the Sparkle key.

Not done yet: network device discovery (enter the address manually; USB
REMOTE at 172.20.0.1 works without setup).
