import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/domain/sync/conflict_summary.dart';
import 'package:recipe_book/domain/sync/merge.dart';
import 'package:recipe_book/domain/sync/stamp.dart';
import 'package:recipe_book/domain/sync/tombstone.dart';

/// The difference rows the review screen shows.
///
/// The one property that matters: it reads the same canonical form the merge
/// compared on, so it can never show a difference that was not one — a
/// `photoPath` or a stamp is machinery, not a question for a person.
void main() {
  final tie = Stamp(DateTime.utc(2026, 8, 20, 12), 'both');

  StampedRecord record(Map<String, dynamic> json) => StampedRecord(
    kind: EntityKind.recipe,
    id: 'r1',
    json: {'id': 'r1', ...json},
    stamp: tie,
    label: json['title'] as String? ?? 'Something',
  );

  Conflict editEdit(Map<String, dynamic> mine, Map<String, dynamic> theirs) =>
      Conflict(
        kind: EntityKind.recipe,
        id: 'r1',
        label: 'Chicken Katsu',
        reason: ConflictReason.editEdit,
        local: record(mine),
        remote: record(theirs),
      );

  test('a title-only difference is exactly one row', () {
    final rows = describeConflict(
      editEdit(
        {'title': 'Chicken Katsu', 'servings': 4},
        {'title': 'Katsu Curry', 'servings': 4},
      ),
    );

    expect(rows, hasLength(1));
    expect(rows.single.label, 'Title');
    expect(rows.single.mine, 'Chicken Katsu');
    expect(rows.single.theirs, 'Katsu Curry');
  });

  test('non-portable fields are never shown as differences', () {
    final rows = describeConflict(
      editEdit(
        {
          'title': 'Same',
          'notes': 'same note',
          'photoPath': r'C:\laptop\photos\a.jpg',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'updatedBy': 'laptop',
        },
        {
          'title': 'Same',
          'notes': 'different note',
          'photoPath': '/data/android/photos/b.jpg',
          'updatedAt': '2026-02-02T00:00:00.000Z',
          'updatedBy': 'phone',
        },
      ),
    );

    expect(rows.map((r) => r.label), ['Notes']);
  });

  test('list fields summarise as counts rather than dumping content', () {
    final rows = describeConflict(
      editEdit(
        {
          'title': 'Same',
          'ingredients': [
            {'id': 'i1', 'name': 'chicken', 'order': 0},
          ],
        },
        {
          'title': 'Same',
          'ingredients': [
            {'id': 'i1', 'name': 'chicken', 'order': 0},
            {'id': 'i2', 'name': 'panko', 'order': 1},
          ],
        },
      ),
    );

    expect(rows.single.label, 'Ingredients');
    expect(rows.single.mine, '1 ingredients');
    expect(rows.single.theirs, '2 ingredients');
  });

  test('an edit-delete conflict is one row, not a field-by-field diff', () {
    final conflict = Conflict(
      kind: EntityKind.recipe,
      id: 'r1',
      label: 'Chicken Katsu',
      reason: ConflictReason.editDelete,
      local: record({'title': 'Chicken Katsu'}),
      remoteDelete: Tombstone(kind: EntityKind.recipe, id: 'r1', stamp: tie),
    );

    final rows = describeConflict(conflict);
    expect(rows, hasLength(1));
    expect(rows.single.theirs, isNull, reason: 'that side deleted it');
    expect(rows.single.mine, isNotNull);
  });

  test('a difference hiding in an unlabelled field still shows something', () {
    // The merge compares canonical content, which includes fields the screen
    // has no label for. An empty card would look like a bug; the fallback row
    // at least says the two differ.
    final rows = describeConflict(
      editEdit(
        {'title': 'Same', 'mealTypeId': 'mt-1'},
        {'title': 'Same', 'mealTypeId': 'mt-2'},
      ),
    );

    expect(rows, hasLength(1));
    expect(rows.single.label, 'Details');
  });

  test('the entity kind reads as words', () {
    expect(EntityKind.planEntry.singular, 'planned meal');
    expect(EntityKind.pantryItem.singular, 'pantry item');
  });
}
