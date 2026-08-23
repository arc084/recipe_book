import 'dart:io';

import '../../domain/sync/conflict_summary.dart';
import '../../state/app_state.dart';
import '../sync_service.dart';
import 'cloud_folder.dart';
import 'device_post.dart';

/// What one run through the folder did.
class CloudOutcome {
  const CloudOutcome({
    this.devicesRead = 0,
    this.received = 0,
    this.photosPulled = 0,
    this.photosPushed = 0,
    this.conflicts = 0,
    this.skipped = const [],
    this.unavailable = false,
  });

  final int devicesRead;
  final int received;
  final int photosPulled;
  final int photosPushed;

  /// Ties the merge could not settle. When this is non-zero nothing was
  /// applied and a review is waiting.
  final int conflicts;

  final List<CloudSkip> skipped;

  /// The folder was not reachable — an unmounted drive, a provider signed out.
  /// Not an error, just a reason nothing happened.
  final bool unavailable;

  bool get isEmpty =>
      received == 0 && photosPulled == 0 && photosPushed == 0 && !unavailable;

  String get message {
    if (unavailable) return 'That folder is not reachable right now.';
    if (conflicts > 0) {
      return '$conflicts ${conflicts == 1 ? 'thing' : 'things'} changed in two '
          'places at once — pick which to keep.';
    }
    if (isEmpty) return 'Already up to date.';
    final parts = <String>[
      if (received > 0) '$received in',
      if (photosPulled > 0) '$photosPulled ${_photos(photosPulled)} in',
      if (photosPushed > 0) '$photosPushed ${_photos(photosPushed)} out',
    ];
    return 'Synced · ${parts.join(' · ')}';
  }

  static String _photos(int n) => n == 1 ? 'photo' : 'photos';
}

/// Syncs through a folder someone else keeps in step.
///
/// Deliberately the *same* merge the local-network transport uses. Two merges
/// that could disagree about what an edit means would be worse than having only
/// one transport, so everything here is about moving snapshots in and out —
/// none of it decides anything.
class CloudSync {
  CloudSync(this._app, this._folder, {this.reviews});

  final AppState _app;
  final CloudFolder _folder;

  /// Where a tie goes to be asked about. Optional so the exchange can be
  /// tested without a service behind it; when absent, a tie simply stops the
  /// run without applying anything, which is the same safe outcome.
  final SyncService? reviews;

  /// Reads every other device's post, merges them, writes ours back.
  ///
  /// Our own post goes **last**, so it reflects everything just merged rather
  /// than the state we started from. A device that read our post in between
  /// would otherwise be handed a snapshot already known to be stale.
  Future<CloudOutcome> run() async {
    if (!await _folder.isAvailable()) {
      return const CloudOutcome(unavailable: true);
    }
    await _folder.ensure();

    final deviceId = _app.settings.deviceId;
    if (deviceId == null) return const CloudOutcome();

    final read = await _folder.readOthers(deviceId);

    var received = 0;
    for (final post in read.posts) {
      final plan = _app.planMerge(post.library, post.pantry);
      final unresolved = [
        ...plan.library.unresolved,
        ...plan.pantry.unresolved,
      ];

      if (unresolved.isNotEmpty) {
        // Stop at the first device that raises a tie. Merging the rest would
        // mean asking the user about several devices at once, and the answers
        // to one set could change the next.
        reviews?.openReview(
          conflicts: unresolved,
          peerLibrary: post.library,
          peerPantry: post.pantry,
          source: TransferSource(
            peerName: post.deviceName,
            createdAt: post.writtenAt,
          ),
        );
        return CloudOutcome(
          devicesRead: read.posts.length,
          received: received,
          conflicts: unresolved.length,
          skipped: read.skipped,
        );
      }

      await _app.applyMerge(plan.library, plan.pantry);
      received +=
          plan.library.stats.totalAdded +
          plan.library.stats.totalUpdated +
          plan.pantry.stats.totalAdded +
          plan.pantry.stats.totalUpdated;
    }

    final pulled = await _pullPhotos();
    final pushed = await _pushPhotos();
    await _writeOurs(deviceId);

    return CloudOutcome(
      devicesRead: read.posts.length,
      received: received,
      photosPulled: pulled,
      photosPushed: pushed,
      skipped: read.skipped,
    );
  }

  /// Fetches photographs this device's recipes name but does not hold.
  Future<int> _pullPhotos() async {
    var count = 0;
    for (final hash in await _app.missingPhotoHashes()) {
      final bytes = await _folder.readPhoto(hash);
      if (bytes == null) continue;
      // storePhotoBytes verifies the hash before writing, so a corrupted file
      // in the folder cannot become a corrupted photo here.
      await _app.storePhotoBytes(hash, bytes);
      count++;
    }
    return count;
  }

  /// Puts photographs this device holds into the folder for the others.
  Future<int> _pushPhotos() async {
    final present = await _folder.photoHashes();
    var count = 0;
    for (final hash in _app.localPhotoHashes()) {
      if (present.contains(hash)) continue;
      final bytes = await _app.photoBytesByHash(hash);
      if (bytes == null) continue;
      await _folder.writePhoto(hash, bytes);
      count++;
    }
    return count;
  }

  Future<void> _writeOurs(String deviceId) async {
    await _folder.writeMine(
      DevicePost(
        deviceId: deviceId,
        deviceName: _app.settings.deviceName,
        platform: Platform.operatingSystem,
        writtenAt: DateTime.now().toUtc(),
        library: _app.library,
        pantry: _app.pantry,
        wantPhotos: await _app.missingPhotoHashes(),
      ),
    );
  }
}
