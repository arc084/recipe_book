import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../theme/tokens.dart';
import '../../update/release_check.dart';
import '../../update/updater.dart';
import '../widgets/primitives.dart';

/// The update check in Settings: one row, one state at a time.
///
/// Checks only when pressed — never on launch. The app is offline by
/// design, and a background call would quietly make that untrue. Every
/// outcome, including the failures, lands in this same row rather than a
/// dialog: a failed check that cannot be seen is worse than no button.
class UpdateRow extends StatefulWidget {
  const UpdateRow({
    super.key,
    required this.updater,
    required this.platform,
    required this.runningVersion,
    required this.onDownloaded,
    this.downloadDir,
  });

  final Updater updater;
  final UpdatePlatform platform;
  final String runningVersion;

  /// Takes the downloaded artefact the last mile — the system installer on
  /// Android, unpacking beside the install on Windows — and returns the
  /// sentence the row shows afterwards.
  final Future<String> Function(File file, AvailableUpdate update)
  onDownloaded;

  /// Where artefacts land; the platform temp directory unless a test says
  /// otherwise.
  final Future<Directory> Function()? downloadDir;

  @override
  State<UpdateRow> createState() => _UpdateRowState();
}

enum _Phase { idle, checking, upToDate, available, downloading, done, failed }

class _UpdateRowState extends State<UpdateRow> {
  _Phase _phase = _Phase.idle;

  /// What the current phase has to say — the failure reason, the missing
  /// platform sentence, or the hand-off outcome.
  String? _message;

  AvailableUpdate? _update;
  DateTime? _checkedAt;
  int _received = 0;
  int _total = 0;
  bool _cancelRequested = false;

  /// Bumped whenever the user cancels or restarts, so an answer from an
  /// abandoned check cannot overwrite the state that replaced it.
  int _generation = 0;

  String get _platformName => switch (widget.platform) {
    UpdatePlatform.windows => 'Windows',
    UpdatePlatform.android => 'Android',
  };

  Future<void> _check() async {
    final generation = ++_generation;
    setState(() {
      _phase = _Phase.checking;
      _message = null;
      _update = null;
    });

    final result = await widget.updater.check(
      widget.runningVersion,
      widget.platform,
    );
    if (!mounted || generation != _generation) return;

    setState(() {
      switch (result) {
        case UpToDate():
          _phase = _Phase.upToDate;
          _checkedAt = DateTime.now();
        case UpdateAvailable(:final update):
          _phase = _Phase.available;
          _update = update;
        case NotForThisPlatform(:final version):
          _phase = _Phase.failed;
          _message =
              '$version exists, but was published with no '
              '$_platformName build.';
        case MalformedRelease(:final reason):
          _phase = _Phase.failed;
          _message = reason;
        case CheckFailed(:final reason):
          _phase = _Phase.failed;
          _message = reason;
      }
    });
  }

  Future<void> _download() async {
    final update = _update!;
    final generation = ++_generation;
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = update.sizeBytes;
      _cancelRequested = false;
    });

    try {
      final dir =
          await (widget.downloadDir?.call() ?? getTemporaryDirectory());
      final file = await widget.updater.download(
        update,
        into: dir,
        onProgress: (received, total) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
        isCancelled: () => _cancelRequested,
      );
      final outcome = await widget.onDownloaded(file, update);
      if (!mounted || generation != _generation) return;
      setState(() {
        _phase = _Phase.done;
        _message = outcome;
      });
    } on DownloadCancelled {
      if (!mounted || generation != _generation) return;
      // The user changed their mind; the offer simply stands again.
      setState(() => _phase = _Phase.available);
    } on DownloadFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _phase = _Phase.failed;
        _message = failure.reason;
      });
    }
  }

  void _cancel() {
    _generation++;
    setState(() {
      if (_phase == _Phase.downloading) {
        _cancelRequested = true;
        _phase = _Phase.available;
      } else {
        _phase = _Phase.idle;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    Text status(String text, {Color? color}) => Text(
      text,
      style: TextStyle(
        fontFamily: t.bodyFamily,
        fontSize: 13,
        height: 1.4,
        color: color ?? t.text,
      ),
    );

    final (Widget left, List<Widget> actions) = switch (_phase) {
      _Phase.idle => (
        status('Version ${widget.runningVersion}'),
        [AppButton('Check for updates', onPressed: _check)],
      ),
      _Phase.checking => (
        Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.accent,
              ),
            ),
            const SizedBox(width: 9),
            status('Asking the releases page…', color: t.textMuted),
          ],
        ),
        [AppButton('Cancel', onPressed: _cancel)],
      ),
      _Phase.upToDate => (
        status(
          '${widget.runningVersion} is the newest release · checked '
          '${DateFormat.Hm().format(_checkedAt!)}',
        ),
        [AppButton('Check for updates', onPressed: _check)],
      ),
      _Phase.available => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            status(
              '${_update!.version} is available '
              '(${(_update!.sizeBytes / 1e6).round()} MB)',
            ),
            if (_update!.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              status(_update!.notes.trim(), color: t.textMuted),
            ],
          ],
        ),
        [
          AppButton(
            'Download',
            kind: ButtonKind.primary,
            onPressed: _download,
          ),
        ],
      ),
      _Phase.downloading => (
        status(
          'Downloading… '
          '${_total == 0 ? 0 : (_received / _total * 100).round()}%',
        ),
        [AppButton('Cancel', onPressed: _cancel)],
      ),
      _Phase.done => (status(_message!), const <Widget>[]),
      _Phase.failed => (
        // No alarm colour — nothing in this app shouts, and the words
        // already say what went wrong.
        status(_message!),
        [AppButton('Check for updates', onPressed: _check)],
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        ...actions,
      ],
    );
  }
}
