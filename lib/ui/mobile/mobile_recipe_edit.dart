import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/sync/merge.dart' show Resolution;
import '../../domain/units.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../recipe/recipe_edit_controller.dart';
import '../settings/conflict_review.dart';
import '../widgets/primitives.dart';
import 'mobile_widgets.dart';

/// Editing a recipe on the phone.
///
/// The same [RecipeEditController] as the desktop, laid out for one thumb:
/// one component open at a time, quantity / unit / name kept as three
/// fields, reordering by dragging the handle. The desktop's two columns do
/// not fit 428dp; the model underneath is identical by construction.
class MobileRecipeEditPage extends StatefulWidget {
  const MobileRecipeEditPage({super.key, required this.recipeId});

  final String recipeId;

  static Future<void> open(BuildContext context, String recipeId) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MobileRecipeEditPage(recipeId: recipeId),
        ),
      );

  @override
  State<MobileRecipeEditPage> createState() => _MobileRecipeEditPageState();
}

class _MobileRecipeEditPageState extends State<MobileRecipeEditPage> {
  late final RecipeEditController _controller;
  late final TextEditingController _title;

  /// The one component whose ingredients and steps are open. Editing happens
  /// a component at a time, which is also how the recipe reads on the phone.
  String? _openComponentId;

  Recipe get _draft => _controller.draft;

  @override
  void initState() {
    super.initState();
    _controller = RecipeEditController(
      context.read<AppState>().recipe(widget.recipeId)!,
    );
    _controller.addListener(() => setState(() {}));
    _title = TextEditingController(text: _draft.title);
    _openComponentId = _draft.orderedComponents.isEmpty
        ? null
        : _draft.orderedComponents.first.id;
  }

  @override
  void dispose() {
    _controller.dispose();
    _title.dispose();
    super.dispose();
  }

  // ── Leaving ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final app = context.read<AppState>();
    switch (_controller.save(app)) {
      case SaveOutcome.saved:
        if (!mounted) return;
        Navigator.of(context).pop();
      case SaveOutcome.stale:
        // A sync moved the recipe while the draft was open. Not a fault, a
        // question — the same question a merge asks, on the same card.
        final resolution = await reviewStaleDraft(
          context,
          draft: _draft,
          stored: app.recipe(_draft.id),
          isPhone: true,
        );
        if (!mounted || resolution == null) return;
        switch (resolution) {
          case Resolution.takeLocal:
            _controller.saveAnyway(app);
            Navigator.of(context).pop();
          case Resolution.takeRemote:
            _controller.discard();
            Navigator.of(context).pop();
        }
    }
  }

  Future<void> _leave() async {
    if (!_controller.isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showPhoneSheet<bool>(
      context,
      title: 'Leave without saving?',
      subtitle: 'The recipe stays as it was before you started.',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetRow(
            icon: Icons.delete_outline,
            title: 'Discard the changes',
            accent: true,
            onTap: () => Navigator.of(sheet).pop(true),
          ),
          SheetRow(
            icon: Icons.edit_outlined,
            title: 'Keep editing',
            onTap: () => Navigator.of(sheet).pop(false),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    _controller.discard();
    Navigator.of(context).pop();
  }

  // ── Sheets ──────────────────────────────────────────────────────────────

  /// The phone's stand-in for the desktop's [promptForText] dialog.
  Future<String?> _promptInSheet({required String title, String? hint}) {
    final field = TextEditingController();
    return showPhoneSheet<String>(
      context,
      title: title,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: field,
                hint: hint,
                height: 44,
                autofocus: true,
                onSubmitted: (v) => Navigator.of(sheet).pop(v),
              ),
            ),
            const SizedBox(width: 10),
            AppButton(
              'Add',
              kind: ButtonKind.primary,
              height: 44,
              onPressed: () => Navigator.of(sheet).pop(field.text),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      // The sheet owns nothing after it closes.
      Future.microtask(field.dispose);
    });
  }

  Future<void> _pickMealType() async {
    final app = context.read<AppState>();
    final picked = await showPhoneSheet<String>(
      context,
      title: 'Meal type',
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          for (final type in app.mealTypes)
            SheetRow(
              icon: type.id == _draft.mealTypeId
                  ? Icons.check
                  : Icons.circle_outlined,
              title: type.name,
              accent: type.id == _draft.mealTypeId,
              onTap: () => Navigator.of(sheet).pop(type.id),
            ),
          SheetRow(
            icon: Icons.add,
            title: 'New type',
            accent: true,
            onTap: () => Navigator.of(sheet).pop('__new__'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == '__new__') {
      final name = await _promptInSheet(title: 'New meal type', hint: 'Brunch');
      if (name == null || name.trim().isEmpty || !mounted) return;
      final type = context.read<AppState>().addMealType(name.trim());
      _controller.change(() => _draft.mealTypeId = type.id);
      return;
    }
    _controller.change(() => _draft.mealTypeId = picked);
  }

  Future<void> _addComponent() async {
    final name = await _promptInSheet(title: 'New component', hint: 'Breading');
    if (name == null || name.trim().isEmpty) return;
    final added = _controller.addComponent(name.trim());
    setState(() => _openComponentId = added.id);
  }

  Future<void> _addTag() async {
    final tag = await _promptInSheet(title: 'Add a tag', hint: 'high-protein');
    if (tag == null || tag.trim().isEmpty) return;
    _controller.change(() => _draft.tags.add(tag.trim()));
  }

  // ── Layout ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dirty = _controller.isDirty;

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      size: 21,
                      color: t.textSecondary,
                    ),
                    onPressed: _leave,
                  ),
                  Expanded(
                    child: AppTextField(
                      controller: _title,
                      hint: 'Recipe title',
                      height: 44,
                      fontSize: 16,
                      onChanged: (v) =>
                          _controller.change(() => _draft.title = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    dirty ? Icons.edit_outlined : Icons.check,
                    size: 16,
                    color: dirty ? t.accent : t.textFaint,
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    'Save',
                    kind: ButtonKind.primary,
                    height: 38,
                    onPressed: dirty ? _save : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Row(
                    children: [
                      TouchChip(
                        label:
                            context
                                .watch<AppState>()
                                .mealType(_draft.mealTypeId)
                                ?.name ??
                            'Meal type',
                        selected: true,
                        onTap: _pickMealType,
                      ),
                      const SizedBox(width: 10),
                      _NumberBox(
                        label: 'servings',
                        value: _draft.servings.toDouble(),
                        onChanged: (v) => _controller.change(
                          () => _draft.servings = v?.round() ?? 1,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _NumberBox(
                        label: 'min',
                        value: _draft.totalMinutes?.toDouble(),
                        onChanged: (v) => _controller.change(
                          () => _draft.totalMinutes = v?.round(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final tag in _draft.tags)
                        Tag(
                          tag,
                          style: TagStyle.outline,
                          trailing: GestureDetector(
                            onTap: () => _controller.change(
                              () => _draft.tags.remove(tag),
                            ),
                            child: Icon(
                              Icons.close,
                              size: 11,
                              color: t.textMuted,
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: _addTag,
                        child: Text(
                          '＋ tag',
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 12,
                            color: t.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      SectionLabel('Components'),
                      const Spacer(),
                      AppButton(
                        '＋ component',
                        kind: ButtonKind.ghost,
                        fontSize: 11,
                        height: 26,
                        onPressed: _addComponent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final c in _draft.orderedComponents) ...[
                    _componentCard(context, c),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 14),
                  SectionLabel('Notes'),
                  const SizedBox(height: 8),
                  _NotesField(
                    value: _draft.notes,
                    onChanged: (v) =>
                        _controller.change(() => _draft.notes = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Components ──────────────────────────────────────────────────────────

  Widget _componentCard(BuildContext context, RecipeComponent c) {
    final t = context.tokens;
    final open = c.id == _openComponentId;

    return Panel(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _openComponentId = open ? null : c.id),
            child: Container(
              color: t.accent.withValues(alpha: 0.08),
              padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: open
                        ? _InlineEdit(
                            value: c.name,
                            fontSize: 11,
                            uppercase: true,
                            color: t.accentText,
                            onChanged: (v) =>
                                _controller.renameComponent(c.id, v),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: SectionLabel(
                              c.name,
                              color: t.accentText,
                              size: 10,
                            ),
                          ),
                  ),
                  if (open)
                    AppIconButton(
                      icon: Icons.delete_outline,
                      size: 30,
                      iconSize: 15,
                      bordered: false,
                      tooltip: 'Remove component',
                      onPressed: () {
                        _controller.removeComponent(c.id);
                        setState(() => _openComponentId = null);
                      },
                    ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: t.textMuted,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          if (open) ...[
            _ingredientList(context, c),
            _addRow(
              context,
              'Add an ingredient',
              () => _controller.addIngredient(c.id),
            ),
            Container(height: 1, color: t.divider),
            _stepList(context, c),
            _addRow(context, 'Add a step', () => _controller.addStep(c.id)),
          ],
        ],
      ),
    );
  }

  Widget _ingredientList(BuildContext context, RecipeComponent c) {
    final lines = _draft.ingredientsOf(c.id);
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) =>
          _controller.reorderIngredient(c.id, from, to),
      children: [
        for (var i = 0; i < lines.length; i++)
          _IngredientRow(
            key: ValueKey(lines[i].id),
            index: i,
            line: lines[i],
            controller: _controller,
          ),
      ],
    );
  }

  Widget _stepList(BuildContext context, RecipeComponent c) {
    final steps = _draft.stepsOf(c.id);
    final numbered = _draft.orderedSteps;
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) => _controller.reorderStep(c.id, from, to),
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            key: ValueKey(steps[i].id),
            index: i,
            // Numbering runs continuously across the whole recipe, the same
            // run every screen numbers by.
            number: numbered.indexOf(steps[i]) + 1,
            step: steps[i],
            controller: _controller,
          ),
      ],
    );
  }

  Widget _addRow(BuildContext context, String label, VoidCallback onTap) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.divider)),
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 14, color: t.accent),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12.5,
                color: t.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

/// One ingredient line: drag handle, then quantity, unit and name as three
/// fields. Three, always — collapsing them breaks serving scaling and pantry
/// matching, which is the basis of the macro engine.
class _IngredientRow extends StatefulWidget {
  const _IngredientRow({
    super.key,
    required this.index,
    required this.line,
    required this.controller,
  });

  final int index;
  final Ingredient line;
  final RecipeEditController controller;

  @override
  State<_IngredientRow> createState() => _IngredientRowState();
}

class _IngredientRowState extends State<_IngredientRow> {
  late final _qty = TextEditingController(
    text: formatAmount(widget.line.quantity),
  );
  late final _unit = TextEditingController(text: widget.line.unit);
  late final _name = TextEditingController(text: widget.line.name);

  @override
  void dispose() {
    _qty.dispose();
    _unit.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final line = widget.line;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.drag_indicator, size: 17, color: t.textFaint),
            ),
          ),
          SizedBox(
            width: 52,
            child: AppTextField(
              controller: _qty,
              hint: 'qty',
              height: 38,
              fontSize: 13,
              filled: false,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) => widget.controller.change(
                () => line.quantity = double.tryParse(v.trim()),
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: AppTextField(
              controller: _unit,
              hint: 'unit',
              height: 38,
              fontSize: 13,
              filled: false,
              onChanged: (v) =>
                  widget.controller.change(() => line.unit = v.trim()),
            ),
          ),
          Expanded(
            child: AppTextField(
              controller: _name,
              hint: 'ingredient',
              height: 38,
              fontSize: 13.5,
              filled: false,
              onChanged: (v) =>
                  widget.controller.change(() => line.name = v),
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            size: 30,
            iconSize: 14,
            bordered: false,
            onPressed: () => widget.controller.removeIngredient(line.id),
          ),
        ],
      ),
    );
  }
}

/// One method step: drag handle, the recipe-wide number, the text.
class _StepRow extends StatefulWidget {
  const _StepRow({
    super.key,
    required this.index,
    required this.number,
    required this.step,
    required this.controller,
  });

  final int index;
  final int number;
  final RecipeStep step;
  final RecipeEditController controller;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  late final _text = TextEditingController(text: widget.step.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.drag_indicator, size: 17, color: t.textFaint),
            ),
          ),
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: t.accent)),
            ),
            child: Text(
              '${widget.number}',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.accent,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _text,
              maxLines: null,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 14,
                height: 1.5,
                color: t.text,
              ),
              cursorColor: t.accent,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'What happens at this step',
                hintStyle: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 14,
                  color: t.textFaint,
                ),
                border: InputBorder.none,
              ),
              onChanged: (v) =>
                  widget.controller.change(() => widget.step.text = v),
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            size: 30,
            iconSize: 14,
            bordered: false,
            onPressed: () => widget.controller.removeStep(widget.step.id),
          ),
        ],
      ),
    );
  }
}

/// A small numeric field with its unit written beside it.
class _NumberBox extends StatelessWidget {
  const _NumberBox({
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
          width: 52,
          child: AppTextField(
            controller: TextEditingController(text: formatAmount(value)),
            height: 34,
            fontSize: 13,
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

/// The component header's rename field — text until touched, like the
/// desktop's inline fields.
class _InlineEdit extends StatefulWidget {
  const _InlineEdit({
    required this.value,
    required this.onChanged,
    this.fontSize = 13,
    this.uppercase = false,
    this.color,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final double fontSize;
  final bool uppercase;
  final Color? color;

  @override
  State<_InlineEdit> createState() => _InlineEditState();
}

class _InlineEditState extends State<_InlineEdit> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = TextStyle(
      fontFamily: t.bodyFamily,
      fontSize: widget.fontSize,
      color: widget.color ?? t.text,
      letterSpacing: widget.uppercase ? 0.08 * widget.fontSize : null,
    );

    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textCapitalization: widget.uppercase
          ? TextCapitalization.characters
          : TextCapitalization.none,
      style: style,
      cursorColor: t.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Component name',
        hintStyle: style.copyWith(color: t.textFaint),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        border: InputBorder.none,
      ),
    );
  }
}

/// Multiline notes, styled like the rest of the phone's fields.
class _NotesField extends StatefulWidget {
  const _NotesField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: t.surface, borderRadius: t.brContainer),
      child: TextField(
        controller: _controller,
        maxLines: null,
        minLines: 3,
        style: TextStyle(
          fontFamily: t.bodyFamily,
          fontSize: 13.5,
          height: 1.55,
          color: t.text,
        ),
        cursorColor: t.accent,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Anything worth remembering next time',
          hintStyle: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 13.5,
            color: t.textFaint,
          ),
          border: InputBorder.none,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
