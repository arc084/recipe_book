import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/database.dart';
import 'package:recipe_book/domain/sync/conflict_summary.dart';
import 'package:recipe_book/domain/sync/merge.dart';
import 'package:recipe_book/domain/sync/stamp.dart';
import 'package:recipe_book/domain/sync/tombstone.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/settings/conflict_review.dart';

/// The review screen itself — the repo's first widget tests.
///
/// A hand-built review, pumped straight into the sheet: no AppState, no
/// sockets, no SyncService. That is the point of `PendingReview` being a plain
/// domain object.
void main() {
  final tie = Stamp(DateTime.utc(2026, 8, 20, 12), 'both');

  StampedRecord record(String id, String title, String notes) => StampedRecord(
    kind: EntityKind.recipe,
    id: id,
    json: {'id': id, 'title': title, 'notes': notes},
    stamp: tie,
    label: title,
  );

  Conflict conflict(String id, String title) => Conflict(
    kind: EntityKind.recipe,
    id: id,
    label: title,
    reason: ConflictReason.editEdit,
    local: record(id, title, 'laptop note'),
    remote: record(id, title, 'phone note'),
  );

  PendingReview review(List<Conflict> conflicts) => PendingReview(
    conflicts: conflicts,
    source: const NetworkPeer(peerName: 'The phone'),
    peerLibrary: LibraryDatabase(),
    peerPantry: PantryDatabase(),
  );

  /// Pumps a host page with a button that opens the sheet, and returns a
  /// record capturing what the sheet eventually resolved to.
  Future<({Future<Map<String, Resolution>?> result})> open(
    WidgetTester tester,
    PendingReview pending,
  ) async {
    late Future<Map<String, Resolution>?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    result = ConflictReviewSheet.open(context, pending),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return (result: result);
  }

  testWidgets('two conflicts render two cards', (tester) async {
    await open(
      tester,
      review([conflict('r1', 'Chicken Katsu'), conflict('r2', 'Brownies')]),
    );

    expect(find.text('Chicken Katsu'), findsOneWidget);
    expect(find.text('Brownies'), findsOneWidget);
    expect(find.text('2 things changed in both places'), findsOneWidget);
    // The peer is named in the choices, not a generic "theirs".
    expect(find.text("Take The phone's"), findsNWidgets(2));
  });

  testWidgets('apply stays disabled until every card is answered', (
    tester,
  ) async {
    final opened = await open(
      tester,
      review([conflict('r1', 'Chicken Katsu'), conflict('r2', 'Brownies')]),
    );

    expect(find.text('2 still to answer.'), findsOneWidget);

    // Answer only the first.
    await tester.tap(find.text("Keep this device's").first);
    await tester.pump();
    expect(find.text('1 still to answer.'), findsOneWidget);

    // Apply must do nothing while a question stands.
    await tester.tap(find.text('Apply 2 answers'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Apply 2 answers'), findsOneWidget, reason: 'still open');

    // Answer the second; now it goes through.
    await tester.tap(find.text("Take The phone's").last);
    await tester.pump();
    expect(find.text('Every question answered.'), findsOneWidget);
    await tester.tap(find.text('Apply 2 answers'));
    await tester.pumpAndSettle();

    expect(await opened.result, {
      'r1': Resolution.takeLocal,
      'r2': Resolution.takeRemote,
    });
  });

  testWidgets('backing out returns null and applies nothing', (tester) async {
    final opened = await open(tester, review([conflict('r1', 'Katsu')]));

    await tester.tap(find.text("Keep this device's"));
    await tester.pump();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(await opened.result, isNull);
  });

  testWidgets('a transfer source explains the file round trip', (tester) async {
    final pending = PendingReview(
      conflicts: [conflict('r1', 'Katsu')],
      source: TransferSource(
        peerName: 'Kitchen laptop',
        createdAt: DateTime.utc(2026, 8, 18, 21, 4),
      ),
      peerLibrary: LibraryDatabase(),
      peerPantry: PantryDatabase(),
    );

    await open(tester, pending);

    expect(find.textContaining('as it was on'), findsOneWidget);
    expect(find.textContaining('send a file back'), findsOneWidget);
  });
}
