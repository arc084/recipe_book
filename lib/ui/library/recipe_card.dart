import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/photo_picker.dart';
import '../widgets/primitives.dart';

/// A card in the Library grid.
///
/// The photo area is a drop target: dropping an image replaces it and it
/// persists. The meta row's calories and protein are the calculated values
/// from pantry items — never a recipe's own listed figures.
class RecipeCard extends StatefulWidget {
  const RecipeCard({super.key, required this.recipe, required this.onOpen});

  final Recipe recipe;
  final VoidCallback onOpen;

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  bool _dragOver = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final r = widget.recipe;

    final totals = app.macros.forRecipe(r);
    final per = totals.perServing;
    final mealType = app.mealType(r.mealTypeId);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: t.brContainer,
            boxShadow: _hover ? t.shadowMd : t.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 120,
                child: DropTarget(
                  onDragEntered: (_) => setState(() => _dragOver = true),
                  onDragExited: (_) => setState(() => _dragOver = false),
                  onDragDone: (detail) {
                    setState(() => _dragOver = false);
                    final file = detail.files.firstOrNull;
                    if (file == null) return;
                    if (!looksLikeImage(file.path)) return;
                    // Take a copy, so the card does not break when the folder
                    // it was dragged from moves.
                    context.read<AppState>().adoptRecipePhoto(r.id, file.path);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RecipePhoto(
                        path: r.photoPath,
                        placeholder: 'Drop a photo of ${r.title}',
                        hovering: _dragOver,
                      ),
                      if (mealType != null)
                        Positioned(
                          left: 9,
                          bottom: 9,
                          child: IgnorePointer(child: Tag(mealType.name)),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    // Up to two tags.
                    SizedBox(
                      height: 19,
                      child: Row(
                        children: [
                          for (var i = 0; i < r.tags.take(2).length; i++) ...[
                            if (i > 0) const SizedBox(width: 5),
                            Flexible(
                              child: Tag(
                                r.tags[i],
                                style: i == 0
                                    ? TagStyle.accent
                                    : TagStyle.neutral,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 11),
                    Container(
                      padding: const EdgeInsets.only(top: 9),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.divider)),
                      ),
                      child: DefaultTextStyle(
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 11,
                          color: t.textMuted,
                          height: 1.2,
                        ),
                        child: Row(
                          children: [
                            _Figure(
                              value: totals.isComplete
                                  ? per.calories.round().toString()
                                  : '~${per.calories.round()}',
                              label: 'cal',
                            ),
                            const SizedBox(width: 12),
                            _Figure(
                              value: '${per.protein.round()}g',
                              label: 'protein',
                            ),
                            const Spacer(),
                            Text(
                              r.totalMinutes == null
                                  ? '—'
                                  : '${r.totalMinutes} min',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(color: t.textStrong, fontSize: 11)),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
