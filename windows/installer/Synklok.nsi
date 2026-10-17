; Synklok for Windows installer (NSIS 3; on the Mac: brew install makensis).
;
; Per-user install, no administrator prompt: %LOCALAPPDATA%\Programs\Synklok,
; a Start menu shortcut, and an entry in Settings > Apps. It is also how
; updates install: WinSparkle runs it with /update, which skips the welcome
; and finish pages, closes after copying and restarts Synklok.
;
; scripts/release-windows.sh builds it with:
;   -DVERSION=1.0.3 -DBUILD=4 -DDISPLAY_VERSION=1.0.3 -DSTAGE=<dir> -DOUTFILE=<exe>
;   [-DSIGN_CMD=<command>]  signs the uninstaller and the installer (Authenticode)
; STAGE holds Synklok.exe, WinSparkle.dll and Acknowledgements.txt.

Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!define APP_EXE "Synklok.exe"
!define UNINSTALLER "Uninstall Synklok.exe"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Synklok"
!define RUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"
; Must match Program.cs and TrayContext.cs.
!define MUTEX "Local\Synklok.Tray.SingleInstance"
!define QUIT_EVENT "Local\Synklok.Tray.Quit"

Name "Synklok"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\Synklok"
BrandingText "Synklok ${DISPLAY_VERSION} · synklok.app"
ShowInstDetails hide
ShowUninstDetails hide

VIProductVersion "${VERSION}.${BUILD}"
VIFileVersion "${VERSION}.${BUILD}"
VIAddVersionKey "ProductName" "Synklok"
VIAddVersionKey "ProductVersion" "${DISPLAY_VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}.${BUILD}"
VIAddVersionKey "FileDescription" "Synklok Setup"
VIAddVersionKey "CompanyName" "John Blais"
VIAddVersionKey "LegalCopyright" "© 2026 John Blais. MIT License."

!ifdef SIGN_CMD
  !uninstfinalize '${SIGN_CMD} "%1"' = 0
  !finalize '${SIGN_CMD} "%1"' = 0
!endif

!include MUI2.nsh
!include LogicLib.nsh
!include FileFunc.nsh
!include WinMessages.nsh

!define MUI_ICON "..\Synklok.Tray\Assets\synklok.ico"
!define MUI_UNICON "..\Synklok.Tray\Assets\synklok.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_ABORTWARNING

Var UpdateMode

!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipWhenUpdating
!define MUI_PAGE_CUSTOMFUNCTION_SHOW WelcomeShow
!define MUI_WELCOMEPAGE_TITLE "Install Synklok ${DISPLAY_VERSION}"
!define MUI_WELCOMEPAGE_TEXT "Synklok keeps your RME M-1620 Pro D's sample rate matched to its MADI input.$\r$\n$\r$\nIt installs for your Windows account only, so no administrator password is needed. It runs in the system tray by the clock and updates itself.$\r$\n$\r$\nClick Install to continue."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipWhenUpdating
!define MUI_FINISHPAGE_TITLE "Synklok is installed"
!define MUI_FINISHPAGE_TEXT "Synklok lives in the system tray. If you don't see the metronome by the clock, click the ^ arrow, and drag the metronome onto the taskbar to keep it in view.$\r$\n$\r$\nLeft-click it for status, right-click for the menu."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Start Synklok now"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; Asks a running Synklok to quit (it listens for QUIT_EVENT), then waits for
; its single-instance mutex to disappear. Copies older than 1.0.3 don't
; listen, so after ~10 s the user is asked to quit it from the tray.
!macro CLOSE_SYNKLOK un
Function ${un}CloseRunningSynklok
  System::Call 'kernel32::OpenEventW(i 0x0002, i 0, w "${QUIT_EVENT}") i .r0'
  ${If} $0 <> 0
    System::Call 'kernel32::SetEvent(i r0)'
    System::Call 'kernel32::CloseHandle(i r0)'
  ${EndIf}
  StrCpy $1 0
  wait:
    System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "${MUTEX}") i .r0'
    ${If} $0 = 0
      Return
    ${EndIf}
    System::Call 'kernel32::CloseHandle(i r0)'
    ${If} $1 >= 40
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Synklok is still running.$\r$\n$\r$\nRight-click the metronome in the system tray, choose Quit Synklok, then click Retry." /SD IDCANCEL IDRETRY retry
      Quit
      retry:
      StrCpy $1 0
    ${EndIf}
    Sleep 250
    IntOp $1 $1 + 1
    Goto wait
FunctionEnd
!macroend
!insertmacro CLOSE_SYNKLOK ""
!insertmacro CLOSE_SYNKLOK "un."

Function .onInit
  StrCpy $UpdateMode 0
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/update" $R1
  ${IfNot} ${Errors}
    StrCpy $UpdateMode 1
    SetAutoClose true
  ${EndIf}
  Call CloseRunningSynklok
FunctionEnd

Function SkipWhenUpdating
  ${If} $UpdateMode = 1
    Abort
  ${EndIf}
FunctionEnd

; The welcome page leads straight to installing, so say so on its button.
Function WelcomeShow
  GetDlgItem $0 $HWNDPARENT 1
  SendMessage $0 ${WM_SETTEXT} 0 "STR:&Install"
FunctionEnd

Section "Synklok"
  SetOutPath "$INSTDIR"
  File "${STAGE}\${APP_EXE}"
  File "${STAGE}\WinSparkle.dll"
  File "${STAGE}\Acknowledgements.txt"
  WriteUninstaller "$INSTDIR\${UNINSTALLER}"

  CreateShortcut "$SMPROGRAMS\Synklok.lnk" "$INSTDIR\${APP_EXE}"

  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "Synklok"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${DISPLAY_VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "John Blais"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\${UNINSTALLER}"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\${UNINSTALLER}" /S'
  WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "https://synklok.app"
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" $0

  ; Launch at login stores the program's path. If it was on (for example for
  ; a test copy run from Downloads), keep it on and point it at this copy.
  ReadRegStr $0 HKCU "${RUN_KEY}" "Synklok"
  ${If} $0 != ""
    WriteRegStr HKCU "${RUN_KEY}" "Synklok" '"$INSTDIR\${APP_EXE}"'
  ${EndIf}

  ${If} $UpdateMode = 1
    Exec '"$INSTDIR\${APP_EXE}"'
  ${EndIf}
SectionEnd

Function un.onInit
  Call un.CloseRunningSynklok
FunctionEnd

; Settings (%APPDATA%\Synklok) and logs (%LOCALAPPDATA%\Synklok) are kept,
; like dragging the Mac app to the Trash.
Section "Uninstall"
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\WinSparkle.dll"
  Delete "$INSTDIR\Acknowledgements.txt"
  Delete "$INSTDIR\${UNINSTALLER}"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\Synklok.lnk"
  DeleteRegKey HKCU "${UNINST_KEY}"
  ReadRegStr $0 HKCU "${RUN_KEY}" "Synklok"
  ${If} $0 == '"$INSTDIR\${APP_EXE}"'
    DeleteRegValue HKCU "${RUN_KEY}" "Synklok"
  ${EndIf}
  ; WinSparkle's update settings.
  DeleteRegKey HKCU "Software\Synklok"
SectionEnd
