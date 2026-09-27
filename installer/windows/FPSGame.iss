; Inno Setup script for the Windows installer.
; Built by the release workflow (windows-latest has Inno Setup 6), or locally:
;   iscc /DAppVersion=0.8.0-beta /DSourceDir=..\..\builds\windows installer\windows\FPSGame.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\builds\windows"
#endif

[Setup]
AppId={{8D5B3E0A-6F2B-4C77-9D3A-2F6A1C0B7E51}
AppName=FPS Game
AppVersion={#AppVersion}
AppPublisher=game-develop
AppPublisherURL=https://github.com/sathirapramudith123/game-develop
DefaultDirName={autopf}\FPS Game
DefaultGroupName=FPS Game
OutputDir=..\..\dist
OutputBaseFilename=FPSGame-{#AppVersion}-windows-setup
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
UninstallDisplayIcon={app}\FPSGame.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "firewall"; Description: "Allow hosting games through Windows Firewall (UDP 7777)"; GroupDescription: "Multiplayer:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\FPSGame.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\libopus_voice.windows.x86_64.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\THIRD_PARTY_LICENSES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\README.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\FPS Game"; Filename: "{app}\FPSGame.exe"
Name: "{group}\Uninstall FPS Game"; Filename: "{uninstallexe}"
Name: "{autodesktop}\FPS Game"; Filename: "{app}\FPSGame.exe"; Tasks: desktopicon

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""FPS Game"" dir=in action=allow protocol=UDP localport=7777 program=""{app}\FPSGame.exe"""; Flags: runhidden; Tasks: firewall
Filename: "{app}\FPSGame.exe"; Description: "{cm:LaunchProgram,FPS Game}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""FPS Game"""; Flags: runhidden; RunOnceId: "RemoveFirewallRule"
