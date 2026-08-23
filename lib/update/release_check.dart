/// The pure half of the update check.
///
/// Parses one GitHub release payload, compares it against the running
/// version, and picks the artefact for this platform. No network anywhere in
/// this file — the edge cases live here, so the tests can too.
library;

/// Which build is asking, and therefore which artefact name matters.
enum UpdatePlatform {
  windows('-windows-x64.zip'),
  android('-android.apk');

  const UpdatePlatform(this.assetSuffix);

  /// How the release step names this platform's artefact.
  final String assetSuffix;
}

/// What a release check concluded. Every outcome is distinct on purpose: a
/// missing artefact or a malformed payload must never read as "up to date".
sealed class ReleaseCheck {
  const ReleaseCheck();
}

class UpToDate extends ReleaseCheck {
  const UpToDate();
}

class UpdateAvailable extends ReleaseCheck {
  const UpdateAvailable(this.update);

  final AvailableUpdate update;
}

/// The release is newer, but was published with no artefact for this
/// platform.
class NotForThisPlatform extends ReleaseCheck {
  const NotForThisPlatform(this.version);

  final String version;
}

/// The payload could not be read as a release.
class MalformedRelease extends ReleaseCheck {
  const MalformedRelease(this.reason);

  final String reason;
}

/// A release newer than what is running.
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.notes,
    required this.artefact,
    required this.sizeBytes,
    required this.publishedAt,
  });

  /// "0.8.0" — the tag stripped of any leading v.
  final String version;

  /// The release body, shown before downloading.
  final String notes;

  /// The asset matching this platform.
  final Uri artefact;

  final int sizeBytes;
  final DateTime publishedAt;
}

/// Reads [release] (one GitHub release payload) against the [running]
/// version and says what, if anything, there is to offer [platform].
ReleaseCheck checkRelease(
  String running,
  Map<String, dynamic> release,
  UpdatePlatform platform,
) {
  final tag = release['tag_name'];
  if (tag is! String) return const MalformedRelease('The payload has no tag.');
  final version = tag.startsWith('v') ? tag.substring(1) : tag;

  final latest = _parseVersion(version);
  if (latest == null) {
    return MalformedRelease('"$tag" does not read as a version.');
  }
  final current = _parseVersion(running);
  if (current == null) {
    return MalformedRelease('Running version "$running" does not parse.');
  }

  // Numeric, part by part — a string comparison would call 0.10.0 older
  // than 0.9.0. Equal or older offers nothing, so a laptop running an
  // unreleased local build is never told to downgrade.
  var newer = false;
  for (var i = 0; i < 3; i++) {
    if (latest[i] == current[i]) continue;
    newer = latest[i] > current[i];
    break;
  }
  if (!newer) return const UpToDate();

  final assets = release['assets'];
  if (assets is! List) {
    return const MalformedRelease('The payload has no asset list.');
  }
  for (final asset in assets) {
    if (asset is! Map<String, dynamic>) continue;
    final name = asset['name'];
    if (name is! String || !name.endsWith(platform.assetSuffix)) continue;

    final url = asset['browser_download_url'];
    final size = asset['size'];
    if (url is! String || size is! int) {
      return const MalformedRelease('The artefact entry is incomplete.');
    }
    return UpdateAvailable(
      AvailableUpdate(
        version: version,
        notes: release['body'] as String? ?? '',
        artefact: Uri.parse(url),
        sizeBytes: size,
        publishedAt:
            DateTime.tryParse(release['published_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
  }
  return NotForThisPlatform(version);
}

/// "1.2.3" as its three numbers, or null for anything else.
List<int>? _parseVersion(String version) {
  final parts = version.split('.');
  if (parts.length != 3) return null;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.contains(null)) return null;
  return numbers.cast<int>();
}
