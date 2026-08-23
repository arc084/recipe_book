import '../../data/database.dart';
import '../../data/migrations.dart';

/// The version of the post format itself, separate from the database schema
/// the post carries. A device on an older build must refuse a post it cannot
/// read rather than half-understand it.
const int kPostVersion = 1;

/// One device's whole state, as it appears in the shared folder.
///
/// A full snapshot rather than a list of changes: the merge is already
/// full-state and idempotent, and a library is a few tens of kilobytes, so a
/// change log would buy compaction and ordering problems and nothing else.
class DevicePost {
  const DevicePost({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.writtenAt,
    required this.library,
    required this.pantry,
    this.wantPhotos = const [],
    this.postVersion = kPostVersion,
  });

  final String deviceId;
  final String deviceName;
  final String platform;

  /// When this device last wrote. Shown in Settings so a folder full of
  /// devices says which are still in use.
  final DateTime writtenAt;

  final LibraryDatabase library;
  final PantryDatabase pantry;

  /// Hashes this device's recipes name but whose bytes it does not hold, so
  /// another device that has them can drop them in the folder.
  final List<String> wantPhotos;

  final int postVersion;

  factory DevicePost.fromJson(Map<String, dynamic> j) {
    final version = (j['postVersion'] as num?)?.toInt() ?? 1;
    if (version > kPostVersion) {
      throw PostTooNewException(found: version, supported: kPostVersion);
    }
    // The databases carry their own schema, and a post from a newer build can
    // hold a newer one. Let the usual migration path decide, so there is one
    // place that knows how to read an old file.
    final librarySchema = schemaOf(j['library'] as Map<String, dynamic>);
    if (librarySchema > kSchemaVersion) {
      throw SchemaTooNewException(
        found: librarySchema,
        supported: kSchemaVersion,
      );
    }

    return DevicePost(
      deviceId: j['deviceId'] as String,
      deviceName: j['deviceName'] as String? ?? 'A device',
      platform: j['platform'] as String? ?? '',
      writtenAt: DateTime.parse(j['writtenAt'] as String),
      library: LibraryDatabase.fromJson(j['library'] as Map<String, dynamic>),
      pantry: PantryDatabase.fromJson(j['pantry'] as Map<String, dynamic>),
      wantPhotos: [
        for (final h in (j['wantPhotos'] as List? ?? [])) h as String,
      ],
      postVersion: version,
    );
  }

  Map<String, dynamic> toJson() => {
    'postVersion': kPostVersion,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'writtenAt': writtenAt.toUtc().toIso8601String(),
    'wantPhotos': wantPhotos,
    'library': library.toJson(),
    'pantry': pantry.toJson(),
  };
}

/// A post written by a build newer than this one.
///
/// Refusing is the only safe answer: reading it with an older reader would drop
/// every field this build does not know about, and writing our own post back
/// would then propagate that loss to every other device.
class PostTooNewException implements Exception {
  const PostTooNewException({required this.found, required this.supported});

  final int found;
  final int supported;

  @override
  String toString() =>
      'That device is running a newer version of Recipe Book (post format '
      '$found, this build reads $supported). Update this device to sync with '
      'it.';
}
