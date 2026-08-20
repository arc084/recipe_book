import '../../data/database.dart';

import 'canonical_content.dart';
import 'merge.dart';
import 'tombstone.dart';

/// One field the two copies disagree about, in the words the user would use.
class FieldDifference {
  const FieldDifference({
    required this.label,
    required this.mine,
    required this.theirs,
  });

  /// "Title", "Ingredients", "Notes" — never a JSON key.
  final String label;

  /// Null when this side deleted the record outright.
  final String? mine;
  final String? theirs;
}

/// A merge paused on questions, and everything the answers replay against.
///
/// Lives in the domain layer rather than on the network service because a
/// review does not need a live connection: answering re-merges the *held*
/// snapshots and applies locally, and the other device converges on the next
/// exchange, whichever transport carries it. That is also why a review can
/// outlive the sockets that produced it, and why the file route can hand the
/// same object to the same screen.
class PendingReview {
  const PendingReview({
    required this.conflicts,
    required this.source,
    required this.peerLibrary,
    required this.peerPantry,
  });

  final List<Conflict> conflicts;
  final ReviewSource source;

  /// The peer's state exactly as it arrived, held so the answers replay
  /// against the same inputs — the merge is a function, so answering is a
  /// replay, never a half-applied mutation.
  final LibraryDatabase peerLibrary;
  final PantryDatabase peerPantry;
}

/// Where the contested copies came from — a live peer or a file.
///
/// The screen words its footer on this: a network peer converges on the next
/// sync by itself, while a file has no route back and the user has to send one.
sealed class ReviewSource {
  const ReviewSource();

  String get peerName;

  /// When the peer's copies were true. A file is a stale snapshot, and the
  /// user is answering about a past state — the screen must say so.
  DateTime? get asOf;
}

class NetworkPeer extends ReviewSource {
  const NetworkPeer({required this.peerName});

  @override
  final String peerName;

  /// A live exchange is as fresh as the session itself.
  @override
  DateTime? get asOf => null;
}

class TransferSource extends ReviewSource {
  const TransferSource({required this.peerName, required this.createdAt});

  @override
  final String peerName;

  final DateTime createdAt;

  @override
  DateTime? get asOf => createdAt;
}

/// What actually differs between the two copies of a contested record.
///
/// Built over the same canonical form the merge compares on, so it can never
/// report a difference that was not one — a `photoPath` or an `updatedAt` is
/// not something to ask a user about, and canonicalisation already dropped
/// them. An empty result is impossible for a genuine conflict: the merge only
/// raises one when the canonical forms differ.
List<FieldDifference> describeConflict(Conflict conflict) {
  // One side deleting is the whole story; field-level differences would be
  // noise under it.
  if (conflict.reason == ConflictReason.editDelete) {
    return [
      FieldDifference(
        label: conflict.kind.singular,
        mine: conflict.local == null ? null : 'kept, and edited',
        theirs: conflict.remote == null ? null : 'kept, and edited',
      ),
    ];
  }

  final mine = conflict.local?.json ?? const <String, dynamic>{};
  final theirs = conflict.remote?.json ?? const <String, dynamic>{};

  final differences = <FieldDifference>[];
  final keys = {...mine.keys, ...theirs.keys};

  for (final key in keys) {
    final label = _fieldLabels[key];
    // A key without a label is machinery (ids, order, cross-references) or
    // non-portable; the user cannot act on it, so it is not shown.
    if (label == null) continue;

    final a = summariseField(conflict.kind, key, mine[key]);
    final b = summariseField(conflict.kind, key, theirs[key]);
    if (a == b) continue;

    differences.add(FieldDifference(label: label, mine: a, theirs: b));
  }

  // Every shown field agreeing while the canonical forms differ means the
  // difference hides in something unlabelled — say so rather than showing an
  // empty card that looks like a bug.
  if (differences.isEmpty && !sameContent(conflict.kind, mine, theirs)) {
    differences.add(
      const FieldDifference(
        label: 'Details',
        mine: 'this device’s version',
        theirs: 'the other version',
      ),
    );
  }

  return differences;
}

/// A field's value as one short human-readable line, or null when absent.
String? summariseField(EntityKind kind, String key, Object? value) {
  if (value == null) return null;

  return switch (key) {
    'ingredients' => '${(value as List).length} ingredients',
    'steps' => '${(value as List).length} steps',
    'components' =>
      (value as List).map((c) => '${(c as Map)['name']}').join(', '),
    'tags' || 'aliases' =>
      (value as List).isEmpty
          ? null
          : (value.map((t) => '$t').toList()..sort()).join(', '),
    'photoHash' => 'a photograph',
    'inStock' => (value as bool) ? 'in stock' : 'run out',
    'isStaple' => (value as bool) ? 'a staple' : 'not a staple',
    'checked' => (value as bool) ? 'checked off' : 'still to buy',
    'servings' => '$value servings',
    'totalMinutes' => '$value min',
    _ => '$value'.trim().isEmpty ? null : '$value',
  };
}

/// JSON keys worth showing, under the names the screens already use.
const _fieldLabels = <String, String>{
  'title': 'Title',
  'name': 'Name',
  'notes': 'Notes',
  'servings': 'Servings',
  'totalMinutes': 'Time',
  'tags': 'Tags',
  'ingredients': 'Ingredients',
  'steps': 'Method',
  'components': 'Components',
  'photoHash': 'Photo',
  'quantity': 'Quantity',
  'checked': 'Checked',
  'recipeId': 'Recipe',
  'group': 'Kept in',
  'aliases': 'Also known as',
  'isStaple': 'Staple',
  'inStock': 'Stock',
  'calories': 'Calories',
  'protein': 'Protein',
  'fat': 'Fat',
  'carbs': 'Carbs',
  'sugar': 'Sugar',
  'brandLabel': 'Brand',
};

/// "recipe", "meal type", … for sentences like "Deleted here".
extension EntityKindWords on EntityKind {
  String get singular => switch (this) {
    EntityKind.recipe => 'recipe',
    EntityKind.mealType => 'meal type',
    EntityKind.aisle => 'aisle',
    EntityKind.grocery => 'grocery item',
    EntityKind.planEntry => 'planned meal',
    EntityKind.pantryItem => 'pantry item',
  };
}
