import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/settings.dart';
import '../../state/app_state.dart';
import '../../sync/discovery.dart';
import '../../sync/protocol.dart';
import '../../sync/sync_client.dart';
import '../../sync/sync_service.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// Adding a device.
///
/// Both platforms can do both halves — which device shows the code and which
/// types it is the user's choice, not something the app decides for them by
/// looking at the screen size.
class PairingSheet extends StatelessWidget {
  const PairingSheet({super.key});

  static Future<void> open(BuildContext context) {
    final t = context.tokens;
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: EdgeInsets.all(t.space(6)),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: t.brLarge,
              boxShadow: t.shadowLg,
            ),
            child: const PairingSheet(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add a device', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: t.space(2)),
        Text(
          'Both devices need to be on the same network. One shows six digits, '
          'the other types them — it does not matter which is which.',
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 12.5,
            height: 1.5,
            color: t.textMuted,
          ),
        ),
        SizedBox(height: t.space(6)),
        Row(
          children: [
            Expanded(
              child: AppButton(
                'Show a code',
                kind: ButtonKind.primary,
                height: 44,
                onPressed: () {
                  Navigator.of(context).pop();
                  _ShowCodeDialog.open(context);
                },
              ),
            ),
            SizedBox(width: t.space(3)),
            Expanded(
              child: AppButton(
                'Enter a code',
                height: 44,
                onPressed: () {
                  Navigator.of(context).pop();
                  _EnterCodeDialog.open(context);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Showing the code
// ═══════════════════════════════════════════════════════════════════════════

class _ShowCodeDialog extends StatefulWidget {
  const _ShowCodeDialog();

  static Future<void> open(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Dialog(
      backgroundColor: Colors.transparent,
      child: _ShowCodeDialog(),
    ),
  );

  @override
  State<_ShowCodeDialog> createState() => _ShowCodeDialogState();
}

class _ShowCodeDialogState extends State<_ShowCodeDialog> {
  PairingOffer? _offer;
  String? _error;
  Timer? _tick;
  int _pairedCount = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final sync = context.read<SyncService>();
    _pairedCount = context.read<AppState>().settings.devices.length;
    try {
      final offer = await sync.offerPairing();
      if (!mounted) return;
      setState(() => _offer = offer);
      // Ticks the countdown, and notices the moment the other device answers.
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final devices = context.read<AppState>().settings.devices;
        if (devices.length > _pairedCount) {
          Navigator.of(context).pop();
          return;
        }
        setState(() {});
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            'Could not start listening. On Windows, allow Recipe Book '
            'through the firewall when asked.\n\n$e',
      );
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    // Stop announcing the moment the user leaves: the app is offline by
    // design and a socket open all day would not fit that.
    context.read<SyncService>().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final offer = _offer;
    final left = offer?.remaining(DateTime.now().toUtc()) ?? Duration.zero;
    final expired = offer != null && left == Duration.zero;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: EdgeInsets.all(t.space(6)),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: t.brLarge,
          boxShadow: t.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Type this on the other device',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: t.space(4)),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  height: 1.5,
                  color: t.accent,
                ),
              )
            else if (offer == null)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(t.space(6)),
                  child: CircularProgressIndicator(color: t.accent),
                ),
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final digit in offer.code.split(''))
                    Container(
                      width: 46,
                      height: 58,
                      margin: EdgeInsets.symmetric(horizontal: t.space(1)),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.ground,
                        borderRadius: t.brContainer,
                        border: Border.fromBorderSide(
                          BorderSide(color: t.divider),
                        ),
                      ),
                      child: Text(
                        digit,
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 26,
                          color: expired ? t.textFaint : t.text,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: t.space(4)),
              Text(
                expired
                    ? 'That code has expired.'
                    : 'Expires in ${left.inMinutes}:'
                          '${(left.inSeconds % 60).toString().padLeft(2, '0')}'
                          ' · three tries',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12,
                  color: expired ? t.accent : t.textMuted,
                ),
              ),
            ],
            SizedBox(height: t.space(6)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (expired) ...[
                  AppButton(
                    'Show a new code',
                    kind: ButtonKind.primary,
                    onPressed: () {
                      setState(() => _offer = null);
                      _start();
                    },
                  ),
                  SizedBox(width: t.space(2)),
                ],
                AppButton('Done', onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Entering the code
// ═══════════════════════════════════════════════════════════════════════════

class _EnterCodeDialog extends StatefulWidget {
  const _EnterCodeDialog();

  static Future<void> open(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      backgroundColor: Colors.transparent,
      child: _EnterCodeDialog(),
    ),
  );

  @override
  State<_EnterCodeDialog> createState() => _EnterCodeDialogState();
}

class _EnterCodeDialogState extends State<_EnterCodeDialog> {
  final _code = TextEditingController();
  StreamSubscription<DiscoveredDevice>? _watching;
  DiscoveredDevice? _target;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    final discovery = await context.read<SyncService>().browse();
    if (!mounted) return;
    // The device offering a code is the one to talk to; anything else on the
    // network is just listening.
    _watching = discovery.onFound.listen((device) {
      if (!mounted) return;
      setState(() => _target ??= device.isPairing ? device : null);
    });
  }

  @override
  void dispose() {
    _watching?.cancel();
    _code.dispose();
    context.read<SyncService>().stop();
    super.dispose();
  }

  Future<void> _submit() async {
    final target = _target;
    if (target == null || _code.text.trim().length != 6) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await context.read<SyncService>().pairWith(
        target.base,
        _code.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } on SyncException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final target = _target;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: EdgeInsets.all(t.space(6)),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: t.brLarge,
          boxShadow: t.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the code',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: t.space(2)),
            Text(
              target == null
                  ? 'Looking for a device showing a code…'
                  : 'Found ${target.name}. Type the six digits it is showing.',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12.5,
                height: 1.5,
                color: target == null ? t.textMuted : t.accent,
              ),
            ),
            SizedBox(height: t.space(4)),
            AppTextField(
              controller: _code,
              hint: '000000',
              height: 52,
              fontSize: 24,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              SizedBox(height: t.space(3)),
              Text(
                _error!,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  height: 1.4,
                  color: t.accent,
                ),
              ),
            ],
            SizedBox(height: t.space(6)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                SizedBox(width: t.space(2)),
                AppButton(
                  _busy ? 'Pairing…' : 'Pair',
                  kind: ButtonKind.primary,
                  onPressed:
                      _busy || target == null || _code.text.trim().length != 6
                      ? null
                      : _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs one sync session against an already-paired device.
Future<void> runSyncSession(BuildContext context, PairedDevice peer) async {
  final sync = context.read<SyncService>();
  final messenger = ScaffoldMessenger.of(context);
  final t = context.tokens;

  void say(String message) => messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 13,
            color: t.text,
          ),
        ),
        backgroundColor: t.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: t.brContainer),
      ),
    );

  say('Looking for ${peer.name}…');

  try {
    final discovery = await sync.browse();
    // Give the peer a couple of announcement rounds to be heard.
    var found = discovery.devices[peer.id];
    for (var i = 0; i < 6 && found == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      found = discovery.devices[peer.id];
    }

    if (found == null) {
      say(
        '${peer.name} did not answer. Open Recipe Book there and make sure '
        'both are on the same Wi-Fi.',
      );
      await sync.stop();
      return;
    }

    final outcome = await sync.syncWith(peer, found.base);
    await sync.stop();

    if (outcome.conflicts > 0) {
      say(
        outcome.message ??
            '${outcome.conflicts} things changed in both places — '
                'open Settings to sort them out.',
      );
    } else {
      say(
        outcome.received == 0
            ? 'Already up to date.'
            : '${outcome.received} brought over from ${peer.name}.',
      );
    }
  } on SyncException catch (e) {
    await sync.stop();
    say(e.message);
  }
}
