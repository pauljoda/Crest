; Crest for Windows, installed for the person running Setup, with no
; administrator: the app in %LOCALAPPDATA%\Crest\Application, its Start menu
; shortcut, its Uninstall entry, and its registration as a browser.
;
; Scripts/windows/package-windows.py stages the Application folder (the engine,
; the core, the interface and update.json) and compiles this script:
;
;   ISCC /DCrestVersion=0.10.170 /DCrestBuild=1170 /DCrestSource=<staged folder>
;        /DCrestOutput=<folder> /DCrestOutputName=<name> Crest.iss
;
; Crest's registration follows Chromium's own layout (ShellUtil in
; chrome/installer/util) with the install mode windows-branding.patch gives
; Crest and no per-user suffix, so the engine finds itself registered and
; reads whether it is the default browser the way Chromium does: the client
; "Crest", the ProgIDs "CrestHTM" and "CrestPDF", and the app user model ID
; "Crest" its windows carry. It declares the links and documents the Mac app
; declares, plus the images Chromium opens.
;
; An update runs this silently (/VERYSILENT /update=1 /relaunch=1) once Crest
; has quit: Setup waits for Crest's processes to end, installs, and opens
; Crest again. Uninstalling keeps the person's browsing data
; (%LOCALAPPDATA%\Crest\User Data) unless they ask to delete it, or pass
; /deletedata=1 to a silent uninstall.

#ifndef CrestVersion
  #error Pass /DCrestVersion=<marketing version>
#endif
#ifndef CrestBuild
  #error Pass /DCrestBuild=<build number>
#endif
#ifndef CrestSource
  #error Pass /DCrestSource=<staged Application folder>
#endif
#ifndef CrestOutput
  #define CrestOutput "."
#endif
#ifndef CrestOutputName
  #define CrestOutputName "Crest-Setup"
#endif

#define CrestRoot "{localappdata}\Crest"
#define CrestExe "chrome.exe"
#define CrestClient "Software\Clients\StartMenuInternet\Crest"
#define CrestCapabilities CrestClient + "\Capabilities"

[Setup]
AppId=Crest
AppName=Crest
AppVersion={#CrestVersion}
AppVerName=Crest {#CrestVersion}
AppPublisher=The Crest Authors
AppPublisherURL=https://crestbrowser.com/
AppSupportURL=https://github.com/crest-browser/Crest/issues
AppUpdatesURL=https://crestbrowser.com/
VersionInfoVersion={#CrestVersion}.{#CrestBuild}
VersionInfoProductVersion={#CrestVersion}
VersionInfoDescription=Crest Setup
VersionInfoCompany=The Crest Authors
VersionInfoCopyright=Copyright The Crest Authors
DefaultDirName={#CrestRoot}\Application
UsePreviousAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
WizardStyle=modern
SetupIconFile=..\..\CrestEngines\Chromium\Overlay\chrome\app\theme\crest\win\crest.ico
UninstallDisplayIcon={app}\{#CrestExe},0
UninstallDisplayName=Crest
SetupMutex=CrestSetup
; Setup itself waits for Crest to quit, so the Restart Manager's own page
; never asks to close it.
CloseApplications=no
RestartApplications=no
ChangesAssociations=yes
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
OutputDir={#CrestOutput}
OutputBaseFilename={#CrestOutputName}
#ifdef CrestSignTool
SignTool=crest
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupAppTitle=Install Crest
SetupWindowTitle=Install Crest
FinishedHeadingLabel=Crest is installed
FinishedLabelNoIcons=Crest is ready to use.
FinishedLabel=Crest is ready to use.

[InstallDelete]
; The interface's bundles and the engine's version manifest are named for
; their build, so an update removes the last build's first.
Type: filesandordirs; Name: "{app}\interface"
Type: files; Name: "{app}\*.*.*.*.manifest"
Type: filesandordirs; Name: "{app}\locales"

[Files]
Source: "{#CrestSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; The icon is named outright, as Chrome's installer names it: Start draws a
; shortcut that carries an app user model ID from its own icon, and shows a
; generic one when the shortcut leaves the icon to its target.
Name: "{userprograms}\Crest"; Filename: "{app}\{#CrestExe}"; WorkingDir: "{app}"; IconFilename: "{app}\{#CrestExe}"; IconIndex: 0; AppUserModelID: "Crest"

[Registry]
; The ProgIDs a link or document Crest opens is handed to, each naming the
; app and its app user model ID.
Root: HKCU; Subkey: "Software\Classes\CrestHTM"; ValueType: string; ValueName: ""; ValueData: "Crest HTML Document"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\CrestHTM"; ValueType: string; ValueName: "AppUserModelId"; ValueData: "Crest"
Root: HKCU; Subkey: "Software\Classes\CrestHTM\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#CrestExe},0"
Root: HKCU; Subkey: "Software\Classes\CrestHTM\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#CrestExe}"" --single-argument %1"
Root: HKCU; Subkey: "Software\Classes\CrestHTM\Application"; ValueType: string; ValueName: "AppUserModelId"; ValueData: "Crest"
Root: HKCU; Subkey: "Software\Classes\CrestHTM\Application"; ValueType: string; ValueName: "ApplicationIcon"; ValueData: "{app}\{#CrestExe},0"
Root: HKCU; Subkey: "Software\Classes\CrestHTM\Application"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Crest"
Root: HKCU; Subkey: "Software\Classes\CrestHTM\Application"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Browse the web with Crest"
Root: HKCU; Subkey: "Software\Classes\CrestHTM\Application"; ValueType: string; ValueName: "ApplicationCompany"; ValueData: "The Crest Authors"

Root: HKCU; Subkey: "Software\Classes\CrestPDF"; ValueType: string; ValueName: ""; ValueData: "Crest PDF Document"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\CrestPDF"; ValueType: string; ValueName: "AppUserModelId"; ValueData: "Crest"
Root: HKCU; Subkey: "Software\Classes\CrestPDF\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#CrestExe},0"
Root: HKCU; Subkey: "Software\Classes\CrestPDF\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#CrestExe}"" --single-argument %1"
Root: HKCU; Subkey: "Software\Classes\CrestPDF\Application"; ValueType: string; ValueName: "AppUserModelId"; ValueData: "Crest"
Root: HKCU; Subkey: "Software\Classes\CrestPDF\Application"; ValueType: string; ValueName: "ApplicationIcon"; ValueData: "{app}\{#CrestExe},0"
Root: HKCU; Subkey: "Software\Classes\CrestPDF\Application"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Crest"
Root: HKCU; Subkey: "Software\Classes\CrestPDF\Application"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Browse the web with Crest"
Root: HKCU; Subkey: "Software\Classes\CrestPDF\Application"; ValueType: string; ValueName: "ApplicationCompany"; ValueData: "The Crest Authors"

; Open With lists Crest for each document it opens.
Root: HKCU; Subkey: "Software\Classes\.htm\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.html\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.shtml\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.xht\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.xhtml\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.mht\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.mhtml\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.svg\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.webp\OpenWithProgids"; ValueType: string; ValueName: "CrestHTM"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "CrestPDF"; ValueData: ""; Flags: uninsdeletevalue

; The browser client Windows' Default apps lists, and what it can open.
Root: HKCU; Subkey: "{#CrestClient}"; ValueType: string; ValueName: ""; ValueData: "Crest"; Flags: uninsdeletekey
Root: HKCU; Subkey: "{#CrestClient}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#CrestExe},0"
Root: HKCU; Subkey: "{#CrestClient}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#CrestExe}"""
Root: HKCU; Subkey: "{#CrestCapabilities}"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Crest"
Root: HKCU; Subkey: "{#CrestCapabilities}"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Browse the web with Crest"
Root: HKCU; Subkey: "{#CrestCapabilities}"; ValueType: string; ValueName: "ApplicationIcon"; ValueData: "{app}\{#CrestExe},0"
Root: HKCU; Subkey: "{#CrestCapabilities}\Startmenu"; ValueType: string; ValueName: "StartMenuInternet"; ValueData: "Crest"
Root: HKCU; Subkey: "{#CrestCapabilities}\URLAssociations"; ValueType: string; ValueName: "http"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\URLAssociations"; ValueType: string; ValueName: "https"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".htm"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".html"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".shtml"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".xht"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".xhtml"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".mht"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".mhtml"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".svg"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".webp"; ValueData: "CrestHTM"
Root: HKCU; Subkey: "{#CrestCapabilities}\FileAssociations"; ValueType: string; ValueName: ".pdf"; ValueData: "CrestPDF"
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "Crest"; ValueData: "{#CrestCapabilities}"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#CrestExe}"; Description: "Open Crest"; Flags: nowait postinstall skipifsilent
; An update opens Crest again where it left off.
Filename: "{app}\{#CrestExe}"; Flags: nowait; Check: RelaunchesCrest

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{#CrestRoot}\Update"

[Code]
const
  // How long an update waits for Crest to finish quitting before it ends
  // what is left, such as a page's process that outlived the browser.
  QuitWaitMilliseconds = 60000;

var
  DeletesBrowsingData: Boolean;

function InstalledCrest: String;
begin
  Result := ExpandConstant('{#CrestRoot}\Application\{#CrestExe}');
end;

function IsUpdate: Boolean;
begin
  Result := ExpandConstant('{param:update|0}') = '1';
end;

function RelaunchesCrest: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;

// Crest's processes: every chrome.exe started from the installed folder.
// Google Chrome's, and every other Chromium's, run from elsewhere.
function CrestProcesses: Variant;
var
  Locator, Service: Variant;
  Path: String;
begin
  Path := InstalledCrest;
  StringChangeEx(Path, '\', '\\', True);
  StringChangeEx(Path, '''', '\''', True);
  Locator := CreateOleObject('WbemScripting.SWbemLocator');
  Service := Locator.ConnectServer('.', 'root\CIMV2');
  Result := Service.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE ExecutablePath = ''' + Path + '''');
end;

function IsCrestRunning: Boolean;
begin
  try
    Result := CrestProcesses.Count > 0;
  except
    Result := False;
  end;
end;

// Waits for Crest to quit, then ends whatever of it is left.
procedure WaitForCrestToQuit;
var
  Waited: Integer;
  Processes: Variant;
  Index: Integer;
begin
  Waited := 0;
  while IsCrestRunning and (Waited < QuitWaitMilliseconds) do begin
    Sleep(250);
    Waited := Waited + 250;
  end;
  try
    Processes := CrestProcesses;
    for Index := 0 to Processes.Count - 1 do
      Processes.ItemIndex(Index).Terminate();
  except
  end;
  while IsCrestRunning and (Waited < QuitWaitMilliseconds + 10000) do begin
    Sleep(250);
    Waited := Waited + 250;
  end;
end;

// Asks the person to quit Crest while it runs; false once they cancel.
function CrestQuits(const Prompt: String; Silent: Boolean): Boolean;
begin
  Result := True;
  while IsCrestRunning do begin
    if Silent or (SuppressibleMsgBox(Prompt, mbInformation, MB_RETRYCANCEL, IDCANCEL) = IDCANCEL) then begin
      Result := False;
      Exit;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if IsUpdate then
    WaitForCrestToQuit
  else if not CrestQuits('Quit Crest to finish installing it.', WizardSilent) then
    Result := 'Crest is open. Quit Crest, then run Setup again.';
end;

function InitializeUninstall: Boolean;
begin
  Result := CrestQuits('Quit Crest to uninstall it.', UninstallSilent);
  if not Result then Exit;
  if UninstallSilent then
    DeletesBrowsingData := ExpandConstant('{param:deletedata|0}') = '1'
  else
    DeletesBrowsingData := MsgBox('Also delete your browsing data, such as your Spaces, history and saved passwords?',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  if DeletesBrowsingData then
    DelTree(ExpandConstant('{#CrestRoot}\User Data'), True, True, True);
  // The product folder goes once nothing of Crest's is left in it.
  RemoveDir(ExpandConstant('{#CrestRoot}'));
end;
