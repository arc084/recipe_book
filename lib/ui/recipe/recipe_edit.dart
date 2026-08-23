import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/units.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../library/library_page.dart' show promptForText;
import '../widgets/primitives.dart';
import 'recipe_edit_controller.dart';

/// Edit mode.
///
/// The layout does not move — the same two columns, with every field writable
/// in place. Quantity, unit and name stay separate fields so scaling and
/// pantry matching keep working. The footer states what is unsaved.
///
/// The edit itself — draft, dirty tracking, every mutation — lives in
/// [RecipeEditController], shared with the phone. This file is only the
/// desktop's two-column arrangement of it.
class RecipeEditView extends StatefulWidget {
  const RecipeEditView({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<RecipeEditView> createState() => _RecipeEditViewState();
}

class _RecipeEditViewState extends State<RecipeEditView> {
  late final RecipeEditController _controller;

  Recipe get _draft => _controller.draft;

  @override
  void initState() {
    super.initState();
    _controller = RecipeEditController(
      context.read<AppState>().recipe(widget.recipeId)!,
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _change(VoidCallback fn) => _controller.change(fn);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, app),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 4, 26, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 322, child: _ingredients(context, app)),
                const SizedBox(width: 22),
                Expanded(child: _method(context)),
              ],
            ),
          ),
        ),
        _footer(context, app),
      ],
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _header(BuildContext context, AppState app) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _InlineField(
                  value: _draft.title,
                  fontSize: 27,
                  heading: true,
                  hint: 'Recipe title',
                  onChanged: (v) => _change(() => _draft.title = v),
                ),
              ),
              const SizedBox(width: 16),
              AppButton(
                'Discard',
                onPressed: () =>
                    context.read<NavController>().editRecipe(false),
              ),
              const SizedBox(width: 8),
              AppButton(
                'Save',
                kind: ButtonKind.primary,
                onPressed: _controller.isDirty ? () => _save(context) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Meal type is a dropdown wherever a recipe is written; the
              // Library's horizontal tabs stay filters, not a picker.
              _MealTypeDropdown(
                value: _draft.mealTypeId,
                onChanged: (id) => _change(() => _draft.mealTypeId = id),
              ),
              const SizedBox(width: 10),
              _NumberField(
                label: 'servings',
                value: _draft.servings.toDouble(),
                onChanged: (v) =>
                    _change(() => _draft.servings = v?.round() ?? 1),
              ),
              const SizedBox(width: 10),
              _NumberField(
                label: 'minutes',
                value: _draft.totalMinutes?.toDouble(),
                onChanged: (v) =>
                    _change(() => _draft.totalMinutes = v?.round()),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final tag in _draft.tags)
                      Tag(
                        tag,
                        style: TagStyle.outline,
                        trailing: GestureDetector(
                          onTap: () => _change(() => _draft.tags.remove(tag)),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Icon(
                              Icons.close,
                              size: 11,
                              color: t.textMuted,
                            ),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () async {
                        final tag = await promptForText(
                          context,
                          title: 'Add a tag',
                          hint: 'high-protein',
                        );
                        if (tag == null || tag.trim().isEmpty) return;
                        _change(() => _draft.tags.add(tag.trim()));
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text(
                          '＋ tag',
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 11,
                            color: t.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save(BuildContext context) {
    // Desktop saves are still last-write-wins; the stale outcome gets its
    // review when the phone editor's conflict surface lands.
    _controller.saveAnyway(context.read<AppState>());
    context.read<NavController>().editRecipe(false);
  }

  // ── Ingredients ─────────────────────────────────────────────────────────

  Widget _ingredients(BuildContext context, AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SectionLabel('Ingredients'),
            const Spacer(),
            AppButton(
              '＋ component',
              kind: ButtonKind.ghost,
              fontSize: 11,
              height: 24,
              onPressed: () async {
                final name = await promptForText(
                  context,
                  title: 'New component',
                  hint: 'Breading',
                );
                if (name == null || name.trim().isEmpty) return;
                _controller.addComponent(name.trim());
              },
            ),
          ],
        ),
        const SizedBox(height: 9),
        Expanded(
          child: Panel(
            clip: true,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final c in _draft.orderedComponents) ...[
                  _componentHeader(context, c),
                  ..._reorderableLines(context, c),
                  _addLineRow(context, c),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _componentHeader(BuildContext context, RecipeComponent c) {
    final t = context.tokens;
    return Container(
      color: t.accent.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(13, 6, 8, 5),
      child: Row(
        children: [
          Expanded(
            child: _InlineField(
              value: c.name,
              fontSize: 10,
              uppercase: true,
              color: t.accentText,
              onChanged: (v) => _controller.renameComponent(c.id, v),
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            size: 20,
            iconSize: 12,
            bordered: false,
            tooltip: 'Remove component',
            onPressed: () => _controller.removeComponent(c.id),
          ),
        ],
      ),
    );
  }

  List<Widget> _reorderableLines(BuildContext context, RecipeComponent c) {
    final lines = _draft.ingredientsOf(c.id);
    return [for (final line in lines) _ingredientRow(context, line)];
  }

  Widget _ingredientRow(BuildContext context, Ingredient line) {
    final t = context.tokens;
    final app = context.read<AppState>();
    final linked = line.pantryItemId == null
        ? null
        : app.pantryItem(line.pantryItemId!);

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            // Rows carry drag handles and an ×.
            Icon(Icons.drag_indicator, size: 15, color: t.textFaint),
            const SizedBox(width: 4),
            SizedBox(
              width: 42,
              child: _InlineField(
                value: formatAmount(line.quantity),
                fontSize: 12.5,
                hint: 'qty',
                onChanged: (v) =>
                    _change(() => line.quantity = double.tryParse(v.trim())),
              ),
            ),
            SizedBox(
              width: 46,
              child: _InlineField(
                value: line.unit,
                fontSize: 12.5,
                hint: 'unit',
                color: t.textMuted,
                onChanged: (v) => _change(() => line.unit = v.trim()),
              ),
            ),
            Expanded(
              child: _InlineField(
                value: line.name,
                fontSize: 13,
                hint: 'ingredient',
                onChanged: (v) => _change(() => line.name = v),
              ),
            ),
            Tooltip(
              message: linked == null
                  ? 'Not linked to a pantry item — saved recipe-only'
                  : 'Linked to ${linked.name}',
              child: Icon(
                linked == null ? Icons.link_off : Icons.link,
                size: 13,
                color: linked == null ? t.textFaint : t.accent,
              ),
            ),
            AppIconButton(
              icon: Icons.close,
              size: 22,
              iconSize: 13,
              bordered: false,
              onPressed: () => _controller.removeIngredient(line.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addLineRow(BuildContext context, RecipeComponent c) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: HoverRow(
        onTap: () => _controller.addIngredient(c.id),
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Icon(Icons.add, size: 13, color: t.accent),
                const SizedBox(width: 9),
                Text(
                  'Add an ingredient',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12,
                    color: t.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Method ──────────────────────────────────────────────────────────────

  Widget _method(BuildContext context) {
    final t = context.tokens;
    final ordered = _draft.orderedSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SectionLabel('Method'),
            const SizedBox(width: 9),
            Text(
              '${ordered.length} steps',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11,
                color: t.textFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(right: 4, bottom: 12),
            children: [
              for (final c in _draft.orderedComponents) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Row(
                    children: [
                      SectionLabel(c.name, color: t.accentText, size: 10),
                      const SizedBox(width: 9),
                      Expanded(child: Container(height: 1, color: t.divider)),
                      const SizedBox(width: 9),
                      AppButton(
                        '＋ step',
                        kind: ButtonKind.ghost,
                        fontSize: 11,
                        height: 22,
                        onPressed: () => _controller.addStep(c.id),
                      ),
                    ],
                  ),
                ),
                for (final step in _draft.stepsOf(c.id))
                  _stepRow(context, ordered.indexOf(step) + 1, step),
              ],
              const SizedBox(height: 20),
              SectionLabel('Notes'),
              const SizedBox(height: 8),
              _InlineField(
                value: _draft.notes,
                fontSize: 13,
                multiline: true,
                hint: 'Anything worth remembering next time',
                onChanged: (v) => _change(() => _draft.notes = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepRow(BuildContext context, int number, RecipeStep step) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.drag_indicator, size: 15, color: t.textFaint),
          const SizedBox(width: 4),
          Container(
            width: 23,
            height: 23,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: t.accent)),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.accent,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: _InlineField(
              value: step.text,
              fontSize: 13.5,
              multiline: true,
              hint: 'What happens at this step',
              onChanged: (v) => _change(() => step.text = v),
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            size: 22,
            iconSize: 13,
            bordered: false,
            onPressed: () => _controller.removeStep(step.id),
          ),
        ],
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────

  Widget _footer(BuildContext context, AppState app) {
    final t = context.tokens;
    final n = _controller.changeCount;
    final dirty = _controller.isDirty;
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 10, 26, 12),
      decoration: BoxDecoration(
        color: t.chrome,
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          Icon(
            dirty ? Icons.edit_outlined : Icons.check,
            size: 15,
            color: dirty ? t.accent : t.textFaint,
          ),
          const SizedBox(width: 9),
          Text(
            dirty
                ? '$n unsaved ${n == 1 ? 'change' : 'changes'}'
                : 'No changes',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 12,
              color: dirty ? t.text : t.textMuted,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

/// A field that looks like text until it is focused.
class _InlineField extends StatefulWidget {
  const _InlineField({
    required this.value,
    required this.onChanged,
    this.fontSize = 13,
    this.hint,
    this.heading = false,
    this.uppercase = false,
    this.multiline = false,
    this.color,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final double fontSize;
  final String? hint;
  final bool heading;
  final bool uppercase;
  final bool multiline;
  final Color? color;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = TextStyle(
      fontFamily: widget.heading ? t.headingFamily : t.bodyFamily,
      fontSize: widget.fontSize,
      height: widget.multiline ? 1.55 : 1.25,
      color: widget.color ?? t.text,
      letterSpacing: widget.uppercase ? 0.08 * widget.fontSize : null,
      fontVariations: [
        FontVariation('wght', widget.heading ? t.headingWeight : 400),
      ],
    );

    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      maxLines: widget.multiline ? null : 1,
      textCapitalization: widget.uppercase
          ? TextCapitalization.characters
          : TextCapitalization.none,
      style: style,
      cursorColor: t.accent,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: style.copyWith(color: t.textFaint),
        contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.transparent),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.transparent),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: t.accent),
        ),
        hoverColor: t.text.withValues(alpha: 0.04),
        filled: true,
        fillColor: Colors.transparent,
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 46,
          child: AppTextField(
            controller: TextEditingController(text: formatAmount(value)),
            height: 28,
            fontSize: 12.5,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            onChanged: (v) => onChanged(double.tryParse(v.trim())),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 11.5,
            color: t.textMuted,
          ),
        ),
      ],
    );
  }
}

/// The meal-type picker — the same six types with the current one ticked, and
/// room to add a new one.
class _MealTypeDropdown extends StatelessWidget {
  const _MealTypeDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final current = app.mealType(value);

    return PopupMenuButton<String>(
      color: t.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: t.brContainer),
      onSelected: (id) async {
        if (id == '__new__') {
          final name = await promptForText(
            context,
            title: 'New meal type',
            hint: 'Brunch',
          );
          if (name == null || name.trim().isEmpty || !context.mounted) return;
          final type = context.read<AppState>().addMealType(name.trim());
          onChanged(type.id);
          return;
        }
        onChanged(id);
      },
      itemBuilder: (context) => [
        for (final type in app.mealTypes)
          PopupMenuItem(
            value: type.id,
            height: 34,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 14,
                  color: type.id == value ? t.accent : Colors.transparent,
                ),
                const SizedBox(width: 9),
                Text(
                  type.name,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 13,
                    color: t.text,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: '__new__',
          height: 34,
          child: Row(
            children: [
              const SizedBox(width: 23),
              Text(
                '＋ New type',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 13,
                  color: t.accent,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.fromBorderSide(BorderSide(color: t.divider)),
          borderRadius: t.brControl,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current?.name ?? 'Meal type',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12.5,
                color: t.text,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more, size: 15, color: t.textMuted),
          ],
        ),
      ),
    );
  }
}
