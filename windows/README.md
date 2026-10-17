# Synklok for Windows

Windows tray-app port of Synklok. Same behaviour as the macOS app: polls the
M-1620 Pro D's control API twice a second and sets its sample rate to match the
MADI input.

| Project | What it is |
|---|---|
| `Synklok.Core` | Device client + sync engine (cross-platform; a port of the Mac `SyncEngine`) |
| `Synklok.Core.Tests` | xUnit tests, including end-to-end against the pretend device |
| `Synklok.Tray` | WinForms system-tray app (`Synklok.exe`) |
| `Synklok.MockDevice` | Pretend M-1620 for testing without hardware (`PretendM1620.exe`) |

Builds on macOS too (`EnableWindowsTargeting`); the tray app only *runs* on Windows.

```bash
# .NET 10 SDK; on John's Mac it lives in ~/.dotnet
dotnet test windows/Synklok.Core.Tests
dotnet publish windows/Synklok.Tray -c Release -r win-x64 --self-contained \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true
swift windows/tools/make-icons.swift windows/Synklok.Tray/Assets   # regenerate .ico files
```

Not done yet: Windows code signing (SmartScreen warns until signed), automatic
updates, and network device discovery (enter the address manually).
