; Inno Setup script for the Windows installer.
;
; Built by .github/workflows/release.yml on a tag, and buildable by hand with:
;
;   ISCC /DAppVersion=0.7.3 windows\installer\recipe_book.iss
;
; The zip is still published alongside this. The two are not interchangeable:
; an installed copy must be updated by a setup exe and an unpacked one by a
; zip, or the update lands as a second install rather than an upgrade. The
; app tells them apart by the marker file written below — see
; lib/update/install_flavour.dart.

#ifndef AppVersion
  #error Pass the version in: ISCC /DAppVersion=0.7.3 recipe_book.iss
#endif

#define AppName "Recipe Book"
#define AppExe "recipe_book.exe"
#define Publisher "arc084"

[Setup]
; Never change this. Inno matches an existing install by AppId, so a new one
; would install 0.7.4 beside 0.7.3 instead of replacing it, leaving two
; uninstall entries and two copies sharing one database.
AppId={{F2701A6F-8491-4A8C-BAFC-84C2485B7633}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
AppPublisherURL=https://github.com/arc084/recipe_book
VersionInfoVersion={#AppVersion}

; Per-user, so no elevation prompt and no Program Files. This is also where
; 0.7.2 was installed by hand, so that copy is upgraded rather than orphaned.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}

; The restart manager closes a running copy when it needs the files, which
; is why the app hands off to this installer and then leaves it alone rather
; than trying to exit from underneath itself.
CloseApplications=yes
RestartApplications=no

OutputDir=..\..\build\installer
OutputBaseFilename=recipe-book-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
; The whole Flutter release bundle: the exe, its DLLs and the data folder.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
// Writes the marker that tells the app it was installed rather than
// unpacked, so it asks for a setup exe next time instead of a zip. Empty on
// purpose — its presence is the whole signal.
procedure CurStepChanged(CurStep: TSetupStep);
var
  Marker: string;
begin
  if CurStep = ssPostInstall then
  begin
    Marker := ExpandConstant('{app}\installed-by-setup');
    SaveStringToFile(Marker, '', False);
  end;
end;

// Whether the app asked to be started again once this is done.
//
// Only the in-app updater passes /RESTARTAPP=1, so a plain silent install —
// someone scripting a first install, say — still finishes without launching
// anything, which is what a silent install should do.
//
// This exists because /RESTARTAPPLICATIONS cannot do the job. The Restart
// Manager only restarts applications that registered themselves for it with
// RegisterApplicationRestart, and a Flutter Windows app never calls that. So
// it happily closed the app and then had nothing to bring back.
function RestartRequested: Boolean;
begin
  Result := ExpandConstant('{param:RESTARTAPP|0}') = '1';
end;

// How many copies of the app are running from this install folder.
//
// WMI is asked for processes by file name, and each one's full path is then
// compared here, so an unpacked zip copy running from somewhere else does
// not count. The path is deliberately not put in the query: a WQL literal
// needs its backslashes doubled, and StringChangeEx in Inno's script engine
// reports the replacements while leaving the string untouched. The query
// was rejected as invalid, the exception below read that as "nothing
// running", and the first version of this check let the uninstall through.
//
// If WMI cannot be reached the answer is still 0 and the uninstall behaves
// as it always did, but it is logged now rather than swallowed.
function RunningCopies: Integer;
var
  Locator, Service, Found, Proc: Variant;
  Exe: string;
  I: Integer;
begin
  Result := 0;
  Exe := ExpandConstant('{app}\{#AppExe}');
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Found := Service.ExecQuery(
      'SELECT ExecutablePath FROM Win32_Process ' +
      'WHERE Name = ''{#AppExe}'' AND ExecutablePath IS NOT NULL');
    for I := 0 to Found.Count - 1 do
    begin
      Proc := Found.ItemIndex(I);
      if CompareText(Proc.ExecutablePath, Exe) = 0 then
        Result := Result + 1;
    end;
  except
    Log('Could not check for a running copy: ' + GetExceptionMessage);
    Result := 0;
  end;
end;

// Refuses to uninstall while the app is open.
//
// CloseApplications only applies to Setup; the uninstaller has no Restart
// Manager step. A running exe and its loaded DLLs cannot be deleted, and a
// per-user uninstaller has no right to queue them for deletion at reboot, so
// they were simply left in the folder — while the uninstall entry, Start
// menu entry and shortcut all went, making it look like a clean removal.
//
// It asks rather than closing the app itself. The app saves a moment after
// each edit and has no save-on-exit, so killing it could lose the last
// change; the user closing it goes through the app's own close.
//
// A silent uninstall cannot be asked, so it takes the default and stops,
// leaving the install whole and exiting non-zero rather than half-removing it.
function InitializeUninstall: Boolean;
begin
  Result := True;
  while RunningCopies > 0 do
  begin
    if SuppressibleMsgBox(
      '{#AppName} is still open. Close it, then choose Retry.' + #13#10 + #13#10 +
      'Its program files cannot be removed while it is running. ' +
      'Your recipes are not affected either way.',
      mbError, MB_RETRYCANCEL, IDCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; The checkbox on the finished page, for someone running Setup by hand.
Filename: "{app}\{#AppExe}"; Description: "Open {#AppName}"; Flags: nowait postinstall skipifsilent

; The updater's restart. Not `postinstall`, so it runs in a silent install
; rather than waiting for a finished page that will never be shown, and
; guarded by Check so only the updater triggers it.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: RestartRequested

[UninstallDelete]
; The marker is written after install, so Inno does not track it and would
; otherwise leave it behind with an empty folder around it. The databases in
; %APPDATA% are deliberately untouched — uninstalling the app is not the same
; as throwing away a recipe collection.
Type: files; Name: "{app}\installed-by-setup"

; Inno removes only the folders it created. A folder that already existed at
; install time — 0.7.2 was installed here by hand, and an uninstall that ran
; with the app open left files behind — is never recorded as created, so it
; survived every later uninstall as an empty "Recipe Book". Removing it only
; when empty means nothing a user put there is touched.
Type: dirifempty; Name: "{app}"
