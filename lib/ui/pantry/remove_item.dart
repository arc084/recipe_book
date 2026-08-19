import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// Removing a pantry item, on either platform.
///
/// This is the destructive one, so it is confirmed and it says what it costs:
/// the macros go, and every recipe drawing on the item keeps its ingredient
/// line but loses the numbers behind it. Running out of something is the far
/// more common case and is a toggle, not this.
Future<bool> confirmRemovePantryItem(
  BuildContext context,
  PantryItem item,
) async {
  final app = context.read<AppState>();
  final usedIn = app.usedIn(item.id);

  final removed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final t = context.tokens;
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
          padding: EdgeInsets.all(t.space(6)),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: t.brLarge,
            boxShadow: t.shadowLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remove ${item.name}?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: t.space(3)),
              Text(
                usedIn.isEmpty
                    ? 'Its macros and other known names are deleted. Nothing '
                          'uses it, so no recipe changes.'
                    : 'Its macros and other known names are deleted. '
                          '${usedIn.length} '
                          '${usedIn.length == 1 ? 'recipe keeps its' : 'recipes keep their'} '
                          'ingredient line but ${usedIn.length == 1 ? 'loses' : 'lose'} '
                          'the numbers behind it, and will be flagged rather '
                          'than counted as zero.',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 13,
                  height: 1.55,
                  color: t.textSecondary,
                ),
              ),
              if (usedIn.isNotEmpty) ...[
                SizedBox(height: t.space(3)),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final row in usedIn.take(6)) Tag(row.recipe.title),
                    if (usedIn.length > 6)
                      Tag(
                        '+${usedIn.length - 6} more',
                        style: TagStyle.outline,
                      ),
                  ],
                ),
              ],
              SizedBox(height: t.space(3)),
              Container(
                padding: EdgeInsets.all(t.space(3)),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.08),
                  borderRadius: t.brContainer,
                ),
                child: Text(
                  'If you have simply run out, mark it as run out instead — '
                  'that keeps the macros and still counts it as missing.',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12,
                    height: 1.5,
                    color: t.textSecondary,
                  ),
                ),
              ),
              SizedBox(height: t.space(6)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    'Mark as run out',
                    onPressed: () {
                      app.setInStock(item.id, false);
                      Navigator.of(context).pop(false);
                    },
                  ),
                  SizedBox(width: t.space(2)),
                  AppButton(
                    'Cancel',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  SizedBox(width: t.space(2)),
                  AppButton(
                    'Remove',
                    kind: ButtonKind.primary,
                    onPressed: () {
                      app.deletePantryItem(item.id);
                      Navigator.of(context).pop(true);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  return removed ?? false;
}
