/// The app's shared-media directory, derived from its app-files path.
///
/// `path_provider` hands Android apps
/// `/storage/emulated/<user>/Android/data/<package>/files`. The sibling
/// `Android/media/<package>` is the one app-specific directory that other
/// apps — the Syncthings and FolderSyncs that actually move files — can still
/// reach under scoped storage, which is what makes it the relay.
///
/// Returns null when the layout is not the documented one — including SD
/// cards, deliberately: the relay lives on primary storage, and a vendor
/// surprise fills nothing rather than pointing a sync app at a guess.
String? androidMediaRelay(String externalFilesPath) {
  final m = RegExp(
    r'^(/storage/emulated/\d+)/Android/data/([^/]+)/files/?$',
  ).firstMatch(externalFilesPath);
  if (m == null) return null;
  return '${m.group(1)}/Android/media/${m.group(2)}';
}
