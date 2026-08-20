import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/sync/conflict_summary.dart';
import '../../domain/sync/merge.dart';
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

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.peerName,
    required this.chosen,
    required this.onChoose,
  });

  final Conflict conflict;
  final String peerName;
  final Resolution? chosen;
  final ValueChanged<Resolution> onChoose;

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
                        : 'Edited here, deleted on $peerName at the same moment.')
                  : 'Edited in both places at the same moment.',
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
                  "Keep this device's",
                  style: chosen == Resolution.takeLocal
                      ? TagStyle.accent
                      : TagStyle.outline,
                  onTap: () => onChoose(Resolution.takeLocal),
                ),
                SizedBox(width: t.space(2)),
                Tag(
                  "Take $peerName's",
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
