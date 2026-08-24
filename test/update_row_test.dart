import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/settings/update_row.dart';
import 'package:recipe_book/update/release_check.dart';
import 'package:recipe_book/update/updater.dart';

/// The Settings row through its states. The updater is faked in memory —
/// its real network and disk behaviour is covered in updater_test.dart, and
/// file IO must not run under a widget test's fake-async zone anyway.
void main() {
  final available = AvailableUpdate(
    version: '0.8.0',
    notes: '- Recipe editing on Android',
    artefact: Uri.parse('https://example.com/recipe-book-0.8.0-android.apk'),
    sizeBytes: 13371337,
    publishedAt: DateTime.utc(2026, 8, 30, 18),
  );

  Future<void> pumpRow(
    WidgetTester tester,
    Updater updater, {
    UpdatePlatform platform = UpdatePlatform.windows,
    Future<String> Function(File file, AvailableUpdate update)? onDownloaded,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: UpdateRow(
            updater: updater,
            platform: platform,
            runningVersion: '0.7.1',
            downloadDir: () async => Directory.systemTemp,
            onDownloaded:
                onDownloaded ?? (file, update) async => 'handed off',
          ),
        ),
      ),
    );
  }

  testWidgets('idle states the running version and offers a check',
      (tester) async {
    await pumpRow(tester, _FakeUpdater(const UpToDate()));

    expect(find.textContaining('Version 0.7.1'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('up to date says so by version', (tester) async {
    await pumpRow(tester, _FakeUpdater(const UpToDate()));

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('0.7.1 is the newest release'),
      findsOneWidget,
    );
  });

  testWidgets('an available update shows version, size, notes and Download',
      (tester) async {
    await pumpRow(tester, _FakeUpdater(UpdateAvailable(available)));

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('0.8.0 is available (13 MB)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Recipe editing on Android'),
      findsOneWidget,
    );
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('a release without this platform build says so by name',
      (tester) async {
    await pumpRow(tester, _FakeUpdater(const NotForThisPlatform('0.8.0')));

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no Windows build'), findsOneWidget);
  });

  testWidgets('a failed check is visible in plain words', (tester) async {
    // A failed check that looks like "up to date" is worse than no button.
    await pumpRow(
      tester,
      _FakeUpdater(const CheckFailed('The releases API answered 403.')),
    );

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The releases API answered 403.'),
      findsOneWidget,
    );
  });

  testWidgets('downloading shows progress and cancel falls back quietly',
      (tester) async {
    final updater = _FakeUpdater(
      UpdateAvailable(available),
      downloadForever: true,
    );
    await pumpRow(tester, updater);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('50%'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Back to the offer — cancelling is not an error.
    expect(find.text('Download'), findsOneWidget);
    expect(find.textContaining('failed'), findsNothing);
  });

  testWidgets('a finished download hands off and shows the outcome',
      (tester) async {
    File? handedFile;
    await pumpRow(
      tester,
      _FakeUpdater(UpdateAvailable(available)),
      onDownloaded: (file, update) async {
        handedFile = file;
        return 'Handed to the Android installer.';
      },
    );

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(handedFile, isNotNull);
    expect(
      find.textContaining('Handed to the Android installer.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed download is visible in plain words', (tester) async {
    await pumpRow(
      tester,
      _FakeUpdater(UpdateAvailable(available), failDownload: true),
    );

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The download answered 404.'),
      findsOneWidget,
    );
  });
}

/// An updater with the network and the disk cut away.
class _FakeUpdater extends Updater {
  _FakeUpdater(
    this.outcome, {
    this.downloadForever = false,
    this.failDownload = false,
  });

  final ReleaseCheck outcome;
  final bool downloadForever;
  final bool failDownload;

  @override
  Future<ReleaseCheck> check(String running, UpdatePlatform platform) async {
    return outcome;
  }

  @override
  Future<File> download(
    AvailableUpdate update, {
    required Directory into,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (failDownload) throw DownloadFailure('The download answered 404.');
    if (!downloadForever) {
      onProgress?.call(update.sizeBytes, update.sizeBytes);
      return File('${into.path}/artefact');
    }
    // Report halfway, then sit until cancelled — through fake-async timers,
    // which a widget test's pumps drive deterministically.
    onProgress?.call(update.sizeBytes ~/ 2, update.sizeBytes);
    final done = Completer<File>();
    late final Timer poll;
    poll = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (isCancelled?.call() ?? false) {
        poll.cancel();
        done.completeError(const DownloadCancelled());
      }
    });
    return done.future;
  }
}
