; Inno Setup script for the Windows installer. Build the app first, then:
;   flutter build windows --release
;   iscc /DAppVersion=1.2.3 windows\installer\via.iss
; Output: build\installer\Via-<version>-windows-setup.exe
;
; Installs per user (no admin prompt) into %LOCALAPPDATA%\Programs\Via. Put the Visual C++
; runtime DLLs (msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll) next to Via.exe in the
; Release folder first so the app runs on machines without the VC++ redistributable (the
; release workflow does this).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define Release "..\..\build\windows\x64\runner\Release"
#define RunKey "Software\Microsoft\Windows\CurrentVersion\Run"
#define StartupApprovedKey "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"

[Setup]
AppId={{8E3B6F0A-4C2D-4B7E-9A51-3F6D2C8B1E47}
AppName=Via
AppVersion={#AppVersion}
AppVerName=Via {#AppVersion}
AppPublisher=Kamofa
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\Via
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=Via-{#AppVersion}-windows-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Via.exe
UninstallDisplayName=Via
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Via keeps running in the tray: close it so its files can be replaced.
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "startup"; Description: "Start Via when I sign in (it runs in the tray to receive items)"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Via"; Filename: "{app}\Via.exe"
Name: "{autodesktop}\Via"; Filename: "{app}\Via.exe"; Tasks: desktopicon

[Registry]
; Same value the app's own "Start with Windows" switch writes (launch_at_startup), so the
; switch shows it as on. Removed on uninstall either way.
Root: HKCU; Subkey: "{#RunKey}"; ValueType: string; ValueName: "Via"; ValueData: "{app}\Via.exe --minimized"; Tasks: startup; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#RunKey}"; ValueType: none; ValueName: "Via"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#StartupApprovedKey}"; ValueType: none; ValueName: "Via"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Via.exe"; Description: "{cm:LaunchProgram,Via}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Quit the tray app, but only this installation's copy (other programs may be called via.exe).
Filename: "powershell.exe"; Parameters: "-NoProfile -NonInteractive -Command ""Get-Process Via -ErrorAction SilentlyContinue | Where-Object {{ $_.Path -like '{app}\*' } | Stop-Process -Force"""; Flags: runhidden; RunOnceId: "StopVia"
