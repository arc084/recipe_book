import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../domain/sync/conflict_summary.dart';
import '../../domain/sync/merge.dart';
import '../../domain/sync/tombstone.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// The questions a merge stopped to ask.
///
/// One card per contested record: what is here, what is there, and a choice.
/// Nothing is preselected — a tie is the one case the stamps genuinely cannot
/// settle, so there is nothing honest to suggest — and nothing is written
/// until every card is answered and Apply is pressed. Backing out loses
/// nothing: the questions simply return on the next sync.
class ConflictReviewSheet extends StatefulWidget {
  const ConflictReviewSheet({super.key, required this.review});

  final PendingReview review;

  /// Returns the answers, or null when the user backed out.
  ///
  /// A dialog on the desktop, a full-screen route on the phone — the same
  /// split `SettingsPage(isPhone:)` already makes.
  static Future<Map<String, Resolution>?> open(
    BuildContext context,
    PendingReview review, {
    bool isPhone = false,
  }) {
    if (isPhone) {
      return Navigator.of(
        context,
        rootNavigator: true,
      ).push<Map<String, Resolution>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => Scaffold(
            backgroundColor: context.tokens.ground,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ConflictReviewSheet(review: review),
              ),
            ),
          ),
        ),
      );
    }

    final t = context.tokens;
    return showDialog<Map<String, Resolution>>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Container(
            padding: EdgeInsets.all(t.space(6)),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: t.brLarge,
              boxShadow: t.shadowLg,
            ),
            child: ConflictReviewSheet(review: review),
          ),
        ),
      ),
    );
  }

  @override
  State<ConflictReviewSheet> createState() => _ConflictReviewSheetState();
}

class _ConflictReviewSheetState extends State<ConflictReviewSheet> {
  final _answers = <String, Resolution>{};

  bool get _complete =>
      widget.review.conflicts.every((c) => _answers.containsKey(c.id));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final review = widget.review;
    final source = review.source;
    final n = review.conflicts.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          n == 1
              ? 'One thing changed in both places'
              : '$n things changed in both places',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: t.space(2)),
        Text(
          switch (source) {
            NetworkPeer() =>
              'These changed here and on ${source.peerName} at the same '
                  'moment, so neither copy is newer. Pick which stays — your '
                  'choice reaches ${source.peerName} on the next sync.',
            TransferSource() =>
              'These changed both here and on ${source.peerName}, as it was '
                  'on ${DateFormat('d MMM HH:mm').format(source.asOf!)}. '
                  'Answering settles it here — send a file back so '
                  '${source.peerName} settles too.',
          },
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 12.5,
            height: 1.5,
            color: t.textMuted,
          ),
        ),
        SizedBox(height: t.space(4)),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: review.conflicts.length,
            separatorBuilder: (_, _) => SizedBox(height: t.space(3)),
            itemBuilder: (context, i) => _ConflictCard(
              conflict: review.conflicts[i],
              peerName: source.peerName,
              chosen: _answers[review.conflicts[i].id],
              onChoose: (r) =>
                  setState(() => _answers[review.conflicts[i].id] = r),
            ),
          ),
        ),
        SizedBox(height: t.space(4)),
        Row(
          children: [
            Expanded(
              child: Text(
                _complete
                    ? 'Every question answered.'
                    : '${n - _answers.length} still to answer.',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 11.5,
                  color: t.textFaint,
                ),
              ),
            ),
            AppButton(
              'Not now',
              onPressed: () => Navigator.of(context).pop(null),
            ),
            SizedBox(width: t.space(2)),
            AppButton(
              n == 1 ? 'Apply' : 'Apply $n answers',
              kind: ButtonKind.primary,
              onPressed: _complete
                  ? () => Navigator.of(context).pop(Map.of(_answers))
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// A draft against what the store now holds — the editor's stale save.
///
/// A sync landed while the recipe was open, so the user has been handed a
/// merge conflict by their own two devices. Same card, same difference rows,
/// same two answers as a merge review; the only difference is that there is
/// exactly one record and no held peer database to replay.
///
/// Returns how to resolve it, or null when the user backed out — the draft
/// then stays open, still unsaved.
Future<Resolution?> reviewStaleDraft(
  BuildContext context, {
  required Recipe draft,
  required Recipe? stored,
  bool isPhone = false,
}) {
  final conflict = Conflict(
    kind: EntityKind.recipe,
    id: draft.id,
    label: draft.title,
    reason: stored == null ? ConflictReason.editDelete : ConflictReason.editEdit,
    local: StampedRecord(
      kind: EntityKind.recipe,
      id: draft.id,
      json: draft.toJson(),
      stamp: draft.stamp,
      label: draft.title,
    ),
    remote: stored == null
        ? null
        : StampedRecord(
            kind: EntityKind.recipe,
            id: stored.id,
            json: stored.toJson(),
            stamp: stored.stamp,
            label: stored.title,
          ),
  );

  final sheet = _StaleDraftSheet(conflict: conflict);

  if (isPhone) {
    return Navigator.of(context, rootNavigator: true).push<Resolution>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: context.tokens.ground,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: sheet,
            ),
          ),
        ),
      ),
    );
  }

  final t = context.tokens;
  return showDialog<Resolution>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Container(
          padding: EdgeInsets.all(t.space(6)),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: t.brLarge,
            boxShadow: t.shadowLg,
          ),
          child: sheet,
        ),
      ),
    ),
  );
}

class _StaleDraftSheet extends StatefulWidget {
  const _StaleDraftSheet({required this.conflict});

  final Conflict conflict;

  @override
  State<_StaleDraftSheet> createState() => _StaleDraftSheetState();
}

class _StaleDraftSheetState extends State<_StaleDraftSheet> {
  Resolution? _chosen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final deleted = widget.conflict.reason == ConflictReason.editDelete;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This recipe changed while you were editing',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: t.space(2)),
        Text(
          deleted
              ? 'A sync deleted it in the meantime. Saving would bring it '
                    'back; letting go keeps it deleted.'
              : 'A sync brought another device’s version in the '
                    'meantime. Pick which one stays — the other is '
                    'overwritten.',
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 12.5,
            height: 1.5,
            color: t.textMuted,
          ),
        ),
        SizedBox(height: t.space(4)),
        Flexible(
          child: SingleChildScrollView(
            child: _ConflictCard(
              conflict: widget.conflict,
              peerName: 'another device',
              chosen: _chosen,
              onChoose: (r) => setState(() => _chosen = r),
              localName: 'Keep my edit',
              remoteName: deleted ? 'Let it stay deleted' : 'Take the synced one',
            ),
          ),
        ),
        SizedBox(height: t.space(4)),
        Row(
          children: [
            const Spacer(),
            AppButton(
              'Keep editing',
              onPressed: () => Navigator.of(context).pop(null),
            ),
            SizedBox(width: t.space(2)),
            AppButton(
              'Apply',
              kind: ButtonKind.primary,
              onPressed: _chosen == null
                  ? null
                  : () => Navigator.of(context).pop(_chosen),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.peerName,
    required this.chosen,
    required this.onChoose,
    this.localName,
    this.remoteName,
  });

  final Conflict conflict;
  final String peerName;
  final Resolution? chosen;
  final ValueChanged<Resolution> onChoose;

  /// Words for the two answers when the merge's defaults don't fit — the
  /// stale-draft review says "Keep my edit", not "Keep this device's".
  final String? localName;
  final String? remoteName;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final differences = describeConflict(conflict);
    final deleted = conflict.reason == ConflictReason.editDelete;

    return Panel(
      child: Padding(
        padding: EdgeInsets.all(t.space(3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    conflict.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 14,
                      color: t.text,
                    ),
                  ),
                ),
                Tag(conflict.kind.singular, dense: true),
              ],
            ),
            SizedBox(height: t.space(1)),
            Text(
              deleted
                  ? (conflict.localDelete != null
                        ? 'Deleted here, edited on $peerName at the same moment.'
                        : (conflict.remote == null && localName != null
                              ? 'Edited here, deleted by the sync.'
                              : 'Edited here, deleted on $peerName at the '
                                    'same moment.'))
                  : (localName != null
                        ? 'Your edit against the version the sync brought.'
                        : 'Edited in both places at the same moment.'),
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.textMuted,
              ),
            ),
            SizedBox(height: t.space(3)),
            // What actually differs, side by side. Never shows a difference
            // that is not one: it reads the same canonical form the merge
            // compared on.
            for (final d in differences) ...[
              _DifferenceRow(difference: d, peerName: peerName),
              SizedBox(height: t.space(2)),
            ],
            SizedBox(height: t.space(1)),
            Row(
              children: [
                Tag(
                  localName ?? "Keep this device's",
                  style: chosen == Resolution.takeLocal
                      ? TagStyle.accent
                      : TagStyle.outline,
                  onTap: () => onChoose(Resolution.takeLocal),
                ),
                SizedBox(width: t.space(2)),
                Tag(
                  remoteName ?? "Take $peerName's",
                  style: chosen == Resolution.takeRemote
                      ? TagStyle.accent
                      : TagStyle.outline,
                  onTap: () => onChoose(Resolution.takeRemote),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DifferenceRow extends StatelessWidget {
  const _DifferenceRow({required this.difference, required this.peerName});

  final FieldDifference difference;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    Widget side(String device, String? value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device,
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 10,
              color: t.textFaint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value ?? '—',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 12.5,
              height: 1.4,
              color: value == null ? t.textFaint : t.textStrong,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(difference.label, size: 9.5, color: t.textMuted),
        SizedBox(height: t.space(1)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            side('This device', difference.mine),
            SizedBox(width: t.space(3)),
            side(peerName, difference.theirs),
          ],
        ),
      ],
    );
  }
}
