#ifndef AppVersion
  #define AppVersion "dev"
#endif

#ifndef StageDir
  #define StageDir "..\\build\\installer\\stage"
#endif

#ifndef OutputDir
  #define OutputDir "..\\build\\installer\\output"
#endif

#ifndef AppPublisher
  #define AppPublisher "Free Software Foundation, Gforth team"
#endif

[Setup]
AppId=GforthNative
AppName=Gforth Native
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://gforth.org/
DefaultDirName={localappdata}\Programs\Gforth
DefaultGroupName=Gforth Native
AllowNoIcons=yes
DisableProgramGroupPage=yes
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ChangesEnvironment=yes
PrivilegesRequired=lowest
SetupIconFile={#StageDir}\gforth.ico
UninstallDisplayIcon={app}\gforth.ico
LicenseFile={#StageDir}\COPYING
OutputDir={#OutputDir}
OutputBaseFilename=gforth-native-{#AppVersion}-x64-setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "modifypath"; Description: "Add Gforth to PATH"; Flags: unchecked
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Gforth Native"; Filename: "{app}\gforth.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Gforth Native"; Filename: "{app}\gforth.exe"; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{autoprograms}\Uninstall Gforth Native"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\gforth.exe"; Description: "Launch Gforth Native"; Flags: nowait postinstall skipifsilent

[Code]
const
  ModPathName = 'modifypath';
  ModPathType = 'user';

function ModPathDir(): TArrayOfString;
begin
  SetArrayLength(Result, 1);
  Result[0] := ExpandConstant('{app}');
end;

#include "..\modpath.iss"

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    CurStepChangedPath();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    CurUninstallStepChangedPath();
  end;
end;
