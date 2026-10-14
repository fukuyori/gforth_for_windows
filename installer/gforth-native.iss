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
; Signing is activated by build-installer.ps1 -Sign (ISCC /DSign + /Ssigntool=...)
#ifdef Sign
SignTool=signtool
SignedUninstaller=yes
#endif

[Tasks]
Name: "modifypath"; Description: "Add Gforth to PATH"; Flags: unchecked
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Gforth Native"; Filename: "{app}\gforth-advanced.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\gforth.ico"
Name: "{autodesktop}\Gforth Native"; Filename: "{app}\gforth-advanced.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\gforth.ico"; Tasks: desktopicon
Name: "{autoprograms}\Uninstall Gforth Native"; Filename: "{uninstallexe}"

[Run]
; The advanced image is generated from [Code] (GenerateAdvancedImage) so that a
; failure can be reported to the user.
Filename: "{app}\gforth-advanced.cmd"; Description: "Launch Gforth Native"; Flags: nowait postinstall skipifsilent

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

// Generate gforth-advanced.fi with the installed gforth-ditc.exe (generate-advanced.ps1
// replaces the shipped image).  A failure is reported instead of silently leaving the
// plain image as the only one.
procedure GenerateAdvancedImage();
var
  ResultCode: Integer;
  LogPath: String;
begin
  LogPath := ExpandConstant('{app}\generate-advanced.log');
  if not WizardSilent then
    WizardForm.StatusLabel.Caption := 'Generating advanced interactive image...';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\generate-advanced.ps1') + '"',
      ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  if (ResultCode <> 0) or (not FileExists(ExpandConstant('{app}\gforth-advanced.fi'))) then begin
    Log('Advanced image generation failed, exit code ' + IntToStr(ResultCode));
    SuppressibleMsgBox(
      'The advanced interactive image (gforth-advanced.fi) could not be generated (exit code ' +
      IntToStr(ResultCode) + ').' + #13#10 + #13#10 +
      'Gforth Native will start in plain mode without the status bar and history.' + #13#10 +
      'Details: ' + LogPath + #13#10 +
      'To retry, run generate-advanced.ps1 in the installation folder.',
      mbError, MB_OK, IDOK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    CurStepChangedPath();
    GenerateAdvancedImage();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    CurUninstallStepChangedPath();
  end;
end;
