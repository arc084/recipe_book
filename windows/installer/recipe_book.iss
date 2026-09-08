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
