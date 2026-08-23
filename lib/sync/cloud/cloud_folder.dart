import 'dart:convert';
import 'dart:io';

import 'device_post.dart';

/// A folder some other program keeps in step across machines.
///
/// The app never talks to Dropbox, OneDrive, Drive or Syncthing — it reads and
/// writes ordinary files and lets whatever the user already runs do the moving.
/// That is what makes this work with every provider at once, and it is why
/// there are no API keys anywhere: a credential shipped inside an open-source
/// binary would not be a credential.
///
/// **One writer per file.** This is the rule the whole layout exists to keep.
/// If two devices wrote one file, the provider would resolve that its own way —
/// `library (conflicted copy).json`, or a silently dropped edit. Each device
/// owns exactly one post, and photographs are named by their own content, so
/// two devices writing the same photo write identical bytes. The provider is
/// never asked to arbitrate anything.
///
/// ```
/// <root>/recipe-book/
///   devices/<deviceId>.json
///   photos/<sha256>
/// ```
class CloudFolder {
  CloudFolder(this.root);

  /// The folder the user chose. The app's own files go in a subfolder of it so
  /// pointing this at the top of a Dropbox does not scatter files through it.
  final Directory root;

  static const _appDir = 'recipe-book';

  /// Marks a file as still being written. Providers upload whatever they find,
  /// so a partly-written post has to be recognisable as one — both to us and
  /// to the person looking at their Dropbox wondering what it is.
  static const partSuffix = '.part';

  Directory get _home =>
      Directory('${root.path}${Platform.pathSeparator}$_appDir');
  Directory get devices =>
      Directory('${_home.path}${Platform.pathSeparator}devices');
  Directory get photos =>
      Directory('${_home.path}${Platform.pathSeparator}photos');

  Future<void> ensure() async {
    for (final d in [_home, devices, photos]) {
      if (!await d.exists()) await d.create(recursive: true);
    }
  }

  /// Whether the folder is reachable right now.
  ///
  /// A cloud folder can vanish underneath the app — an unmounted drive, a
  /// provider signed out, a folder the user moved — and that is not an error
  /// worth a crash, just a reason not to sync this time.
  Future<bool> isAvailable() async {
    try {
      return await root.exists();
    } on FileSystemException {
      return false;
    }
  }

  // ── Posts ─────────────────────────────────────────────────────────────────

  /// Every other device's post, newest first.
  ///
  /// A post that cannot be read is skipped rather than fatal. The likeliest
  /// cause is entirely ordinary — another device is mid-write, or the provider
  /// is mid-download — and the next sync will pick it up once it settles.
  /// Refusing to sync at all because one of four devices is briefly unreadable
  /// would be the wrong trade.
  Future<CloudRead> readOthers(String myDeviceId) async {
    final posts = <DevicePost>[];
    final skipped = <CloudSkip>[];

    if (!await devices.exists()) return CloudRead(posts, skipped);

    await for (final entry in devices.list()) {
      if (entry is! File) continue;
      final name = entry.path.split(Platform.pathSeparator).last;
      if (!name.endsWith('.json') || name.endsWith(partSuffix)) continue;
      if (name == '$myDeviceId.json') continue;

      try {
        final raw = jsonDecode(await entry.readAsString());
        posts.add(DevicePost.fromJson(raw as Map<String, dynamic>));
      } on Object catch (e) {
        skipped.add(CloudSkip(name, e));
      }
    }

    posts.sort((a, b) => b.writtenAt.compareTo(a.writtenAt));
    return CloudRead(posts, skipped);
  }

  /// Writes this device's post, and only this device's.
  Future<void> writeMine(DevicePost post) async {
    await ensure();
    final target = File(
      '${devices.path}${Platform.pathSeparator}${post.deviceId}.json',
    );
    // Same temp-then-rename the databases use, so a reader never sees half a
    // post. The rename is within one directory, which keeps it atomic.
    final part = File('${target.path}$partSuffix');
    await part.writeAsString(
      const JsonEncoder.withIndent('  ').convert(post.toJson()),
      flush: true,
    );
    await part.rename(target.path);
  }

  /// Drops a device that is gone for good.
  Future<void> forget(String deviceId) async {
    final f = File('${devices.path}${Platform.pathSeparator}$deviceId.json');
    if (await f.exists()) await f.delete();
  }

  // ── Photographs ───────────────────────────────────────────────────────────

  /// Named by content, so the same photograph from two devices is one file and
  /// no write can ever disagree with another.
  Future<Set<String>> photoHashes() async {
    if (!await photos.exists()) return {};
    final out = <String>{};
    await for (final entry in photos.list()) {
      if (entry is! File) continue;
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name.endsWith(partSuffix)) continue;
      out.add(name);
    }
    return out;
  }

  Future<List<int>?> readPhoto(String hash) async {
    final f = File('${photos.path}${Platform.pathSeparator}$hash');
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> writePhoto(String hash, List<int> bytes) async {
    await ensure();
    final target = File('${photos.path}${Platform.pathSeparator}$hash');
    if (await target.exists()) return; // content-addressed: already correct
    final part = File('${target.path}$partSuffix');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(target.path);
  }
}

/// What was found in the folder, and what could not be read.
class CloudRead {
  const CloudRead(this.posts, this.skipped);

  final List<DevicePost> posts;

  /// Files that would not parse. Surfaced rather than swallowed, because a post
  /// that is skipped every time is a real problem wearing the disguise of a
  /// transient one.
  final List<CloudSkip> skipped;
}

class CloudSkip {
  const CloudSkip(this.fileName, this.error);

  final String fileName;
  final Object error;
}
