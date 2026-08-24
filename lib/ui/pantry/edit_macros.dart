import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/units.dart';
import '../../labels/label_client.dart';
import '../../labels/label_lookup.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// The only place the numbers are written, and it is on both platforms — it is
/// done with the packet in hand.
///
/// Serving size comes first, then the five values stated against a chosen
/// basis. Saving states how many recipes recalculate.
class EditMacrosDialog extends StatefulWidget {
  const EditMacrosDialog({super.key, required this.item, this.search});

  final PantryItem item;

  /// Injected by tests; the real Open Food Facts client otherwise.
  final Future<List<LabelReference>> Function(String terms)? search;

  static Future<void> open(BuildContext context, PantryItem item) =>
      showDialog<void>(
        context: context,
        builder: (_) => EditMacrosDialog(item: item),
      );

  @override
  State<EditMacrosDialog> createState() => _EditMacrosDialogState();
}

class _EditMacrosDialogState extends State<EditMacrosDialog> {
  late final PantryItem _draft = widget.item.copy();

  late final _serving = TextEditingController(
    text: formatAmount(_draft.servingAmount),
  );
  late final _servingUnit = TextEditingController(text: _draft.servingUnit);
  late final _alt = TextEditingController(text: formatAmount(_draft.altAmount));
  late final _altUnit = TextEditingController(text: _draft.altUnit ?? '');
  late final _pack = TextEditingController(
    text: formatAmount(_draft.packAmount),
  );
  late final _packUnit = TextEditingController(text: _draft.packUnit ?? 'g');
  late final _brand = TextEditingController(text: _draft.brandLabel ?? '');

  late final _calories = TextEditingController(
    text: formatAmount(_draft.calories),
  );
  late final _protein = TextEditingController(
    text: formatAmount(_draft.protein),
  );
  late final _fat = TextEditingController(text: formatAmount(_draft.fat));
  late final _carbs = TextEditingController(text: formatAmount(_draft.carbs));
  late final _sugar = TextEditingController(text: formatAmount(_draft.sugar));

  late final Future<List<LabelReference>> Function(String terms) _search =
      widget.search ?? LabelClient().search;
  late final _query = TextEditingController(text: _draft.name);

  _SearchState _searchState = _SearchState.idle;
  List<LabelReference> _results = const [];
  String? _searchError;
  LabelReference? _picked;

  /// Bumped to orphan an in-flight search the user cancelled or replaced —
  /// its answer arrives, sees a newer generation, and is dropped.
  int _searchGeneration = 0;

  @override
  void dispose() {
    for (final c in [
      _serving,
      _servingUnit,
      _alt,
      _altUnit,
      _pack,
      _packUnit,
      _brand,
      _calories,
      _protein,
      _fat,
      _carbs,
      _sugar,
      _query,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Label search ────────────────────────────────────────────────────────

  Future<void> _runSearch() async {
    final terms = _query.text.trim();
    if (terms.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() {
      _searchState = _SearchState.searching;
      _picked = null;
    });
    try {
      final found = await _search(terms);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = found;
        _searchState = found.isEmpty
            ? _SearchState.nothing
            : _SearchState.results;
      });
    } on LabelSearchException catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchError = e.message;
        _searchState = _SearchState.failed;
      });
    }
  }

  void _cancelSearch() {
    _searchGeneration++;
    setState(() => _searchState = _SearchState.idle);
  }

  void _pick(LabelReference label) {
    final autofill = context.read<AppState>().settings.autofillFromLabels;
    setState(() => _picked = label);
    if (!autofill) return;
    setState(() {
      // The five values are OFF's canonical per-100 g form, so the basis
      // chip follows them — but only when there are values to state.
      if (label.caloriesPer100g != null ||
          label.proteinPer100g != null ||
          label.fatPer100g != null ||
          label.carbsPer100g != null ||
          label.sugarPer100g != null) {
        _draft.basis = MacroBasis.per100g;
      }
      void put(TextEditingController c, double? v) {
        if (v != null) c.text = formatAmount(v);
      }

      put(_calories, label.caloriesPer100g);
      put(_protein, label.proteinPer100g);
      put(_fat, label.fatPer100g);
      put(_carbs, label.carbsPer100g);
      put(_sugar, label.sugarPer100g);
      put(_serving, label.servingAmount);
      if (label.servingUnit != null) _servingUnit.text = label.servingUnit!;
      put(_pack, label.packAmount);
      if (label.packUnit != null) _packUnit.text = label.packUnit!;
      _brand.text = _productName(label);
    });
  }

  String _productName(LabelReference label) =>
      label.brand == null ? label.name : '${label.brand} ${label.name}';

  int get _affectedRecipes {
    final app = context.read<AppState>();
    return app.library.recipes
        .where(
          (r) => r.ingredients.any((i) => i.pantryItemId == widget.item.id),
        )
        .length;
  }

  void _save() {
    final app = context.read<AppState>();
    _draft
      ..servingAmount = double.tryParse(_serving.text.trim())
      ..servingUnit = _servingUnit.text.trim().isEmpty
          ? 'g'
          : _servingUnit.text.trim()
      ..altAmount = double.tryParse(_alt.text.trim())
      ..altUnit = _altUnit.text.trim().isEmpty ? null : _altUnit.text.trim()
      ..packAmount = double.tryParse(_pack.text.trim())
      ..packUnit = _packUnit.text.trim().isEmpty ? null : _packUnit.text.trim()
      ..brandLabel = _brand.text.trim().isEmpty ? null : _brand.text.trim()
      ..calories = double.tryParse(_calories.text.trim())
      ..protein = double.tryParse(_protein.text.trim())
      ..fat = double.tryParse(_fat.text.trim())
      ..carbs = double.tryParse(_carbs.text.trim())
      ..sugar = double.tryParse(_sugar.text.trim())
      ..enteredOn = DateTime.now();

    final n = _affectedRecipes;
    app.savePantryItem(_draft);
    Navigator.of(context).pop();

    final t = context.tokens;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Saved. No recipes use ${_draft.name} yet.'
                : 'Saved. $n ${n == 1 ? 'recipe recalculates' : 'recipes recalculate'}.',
            style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12.5),
          ),
          backgroundColor: t.surface,
          behavior: SnackBarBehavior.floating,
          width: 380,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 540,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: t.brLarge,
          boxShadow: t.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                t.space(4),
                t.space(4),
                t.space(4),
                t.space(2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Macros — ${_draft.name}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Read them off the packet. Everything else in the app is '
                    'calculated from these.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: t.space(4)),
                children: [
                  _searchSection(context),
                  // 1. Serving size comes first.
                  _step(context, '1', 'Serving size'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _field(context, 'Amount', _serving, width: 0),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field(context, 'Unit', _servingUnit, width: 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'An optional second measurement, so a recipe can call for '
                    'a spoonful.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11,
                      color: t.textFaint,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _field(context, 'Which is', _alt, width: 0),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field(context, 'Unit', _altUnit, width: 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _field(context, 'Pack holds', _pack, width: 0),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field(context, 'Unit', _packUnit, width: 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _field(context, 'Product (optional)', _brand, width: 0),

                  const SizedBox(height: 22),
                  // 2. Five values, against a chosen basis.
                  _step(context, '2', 'The five values'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Stated',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 12,
                          color: t.textMuted,
                        ),
                      ),
                      const SizedBox(width: 9),
                      for (final basis in MacroBasis.values) ...[
                        _BasisChip(
                          label: basis.label,
                          selected: _draft.basis == basis,
                          onTap: () => setState(() => _draft.basis = basis),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(context, 'Calories', _calories, width: 0),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field(context, 'Protein g', _protein, width: 0),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _field(context, 'Fat g', _fat, width: 0)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _field(context, 'Carbs g', _carbs, width: 0),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field(context, 'Sugar g', _sugar, width: 0),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: SizedBox()),
                    ],
                  ),

                  const SizedBox(height: 22),
                  // 3. Estimated carries through to every recipe's totals.
                  _step(context, '3', 'Where they came from'),
                  const SizedBox(height: 10),
                  _EstimatedRow(
                    value: _draft.isEstimated,
                    onChanged: (v) => setState(() => _draft.isEstimated = v),
                  ),
                  SizedBox(height: t.space(4)),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(t.space(4)),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _affectedRecipes == 0
                          ? 'No recipes use this yet.'
                          : 'Saving recalculates $_affectedRecipes '
                                '${_affectedRecipes == 1 ? 'recipe' : 'recipes'}.',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11.5,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                  AppButton(
                    'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  AppButton('Save', kind: ButtonKind.primary, onPressed: _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchSection(BuildContext context) {
    final t = context.tokens;
    final searching = _searchState == _SearchState.searching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _step(context, '0', 'Find a label'),
        const SizedBox(height: 6),
        Text(
          'Search Open Food Facts and copy a label instead of typing it. '
          'Nothing is fetched until you tap search.',
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 11,
            color: t.textFaint,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _query,
                hint: 'Product name',
                height: 38,
                fontSize: 13,
                onSubmitted: (_) => _runSearch(),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              searching ? 'Cancel' : 'Search',
              fontSize: 12,
              height: 38,
              onPressed: searching ? _cancelSearch : _runSearch,
            ),
          ],
        ),
        if (searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (_searchState == _SearchState.failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The search failed: $_searchError',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12,
                color: t.text,
              ),
            ),
          ),
        if (_searchState == _SearchState.nothing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Nothing found for "${_query.text.trim()}".',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12,
                color: t.textMuted,
              ),
            ),
          ),
        if (_searchState == _SearchState.results)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [for (final r in _results) _resultRow(context, r)],
            ),
          ),
        if (_picked != null) _referenceCard(context, _picked!),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _resultRow(BuildContext context, LabelReference label) {
    final t = context.tokens;
    return InkWell(
      onTap: () => _pick(label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _productName(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label.caloriesPer100g == null
                  ? 'no kcal'
                  : '${formatAmount(label.caloriesPer100g)} kcal/100 g',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _referenceCard(BuildContext context, LabelReference label) {
    final t = context.tokens;
    String amount(double? v, String suffix) =>
        v == null ? '—' : '${formatAmount(v)}$suffix';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: t.ground, borderRadius: t.brContainer),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _productName(label),
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 12.5,
              color: t.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Per 100 g: ${amount(label.caloriesPer100g, ' kcal')} · '
            '${amount(label.proteinPer100g, ' g protein')} · '
            '${amount(label.fatPer100g, ' g fat')} · '
            '${amount(label.carbsPer100g, ' g carbs')} · '
            '${amount(label.sugarPer100g, ' g sugar')}',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11.5,
              color: t.textMuted,
            ),
          ),
          if (label.servingAmount != null || label.packAmount != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (label.servingAmount != null)
                  'Serving ${formatAmount(label.servingAmount)} '
                      '${label.servingUnit}',
                if (label.packAmount != null)
                  'Pack ${formatAmount(label.packAmount)} ${label.packUnit}',
              ].join(' · '),
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            context.read<AppState>().settings.autofillFromLabels
                ? 'Filled into the form — check and edit before saving.'
                : 'Autofill is off — copy across whatever you trust.',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11,
              color: t.textFaint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, String number, String label) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BorderSide(color: t.accent)),
          ),
          child: Text(
            number,
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11,
              color: t.accent,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SectionLabel(label),
      ],
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    double width = 100,
  }) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5, left: 2),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11,
              color: t.textMuted,
            ),
          ),
        ),
        SizedBox(
          width: width == 0 ? null : width,
          child: AppTextField(controller: controller, height: 32),
        ),
      ],
    );
  }
}

class _BasisChip extends StatelessWidget {
  const _BasisChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tag(
      label,
      style: selected ? TagStyle.accent : TagStyle.outline,
      onTap: onTap,
    );
  }
}

class _EstimatedRow extends StatelessWidget {
  const _EstimatedRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _radio(
          context,
          label: 'Off this product',
          detail: 'The numbers are the ones on the packet in front of you.',
          selected: !value,
          onTap: () => onChanged(false),
        ),
        const SizedBox(height: 8),
        _radio(
          context,
          label: 'Estimated from something similar',
          detail: 'Every recipe carrying these values says so on its totals.',
          selected: value,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }

  Widget _radio(
    BuildContext context, {
    required String label,
    required String detail,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: t.brContainer,
            color: selected ? t.accent.withValues(alpha: 0.08) : null,
            border: Border.fromBorderSide(
              BorderSide(color: selected ? t.accent : t.divider),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? t.accent : Colors.transparent,
                  border: Border.fromBorderSide(
                    BorderSide(
                      color: selected ? t.accent : t.divider,
                      width: 1.5,
                    ),
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.ground,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 13,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        color: t.textMuted,
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

/// Where the label search stands. `nothing` and `failed` are deliberately
/// separate states: an error shown as an empty list would send the user
/// typing a label that the database actually had.
enum _SearchState { idle, searching, results, nothing, failed }
