; Inno Setup 安裝程式（GitHub Actions：iscc /DAppVersion=x.y.z packaging\windows.iss）
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8E3B7C52-4B2F-4C1C-9C55-1E2A6F0B9D11}
AppName=Image Compressor
AppVersion={#AppVersion}
AppPublisher=Toast
DefaultDirName={autopf}\Image Compressor
DefaultGroupName=Image Compressor
DisableProgramGroupPage=yes
; 預設安裝給目前使用者，不需要系統管理員權限
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=ImageCompressor-{#AppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\image_compressor.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Image Compressor"; Filename: "{app}\image_compressor.exe"
Name: "{autodesktop}\Image Compressor"; Filename: "{app}\image_compressor.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\image_compressor.exe"; Description: "{cm:LaunchProgram,Image Compressor}"; Flags: nowait postinstall skipifsilent
