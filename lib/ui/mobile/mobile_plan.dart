import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';
import 'mobile_recipe.dart';
import 'mobile_widgets.dart';

/// The Meal Plan on Android.
///
/// The phone plans **a day at a time** rather than a week — same four slots,
/// same figures, drawn from the same calculated macros.
class MobilePlanPage extends StatefulWidget {
  const MobilePlanPage({super.key});

  @override
  State<MobilePlanPage> createState() => _MobilePlanPageState();
}

class _MobilePlanPageState extends State<MobilePlanPage> {
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
  }

  DateTime get _weekStart => _day.subtract(Duration(days: _day.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final totals = app.dayTotals(_day);
    final missing = app.missingForWeek(_weekStart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MobileHeader(title: 'Meal plan', showSync: false),
        // A week strip, so a day is one tap away.
        SizedBox(
          height: 62,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (var i = 0; i < 7; i++)
                _dayPill(context, app, _weekStart.add(Duration(days: i))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${DateFormat('EEEE d MMMM').format(_day)} · '
                  '${totals.calories.round()} cal · '
                  '${totals.protein.round()}g',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12.5,
                    color: t.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final slot in MealSlot.values) _slot(context, app, slot),
              const SizedBox(height: 10),
              AppButton(
                missing.isEmpty
                    ? 'Nothing missing this week'
                    : 'Add ${missing.length} missing '
                        '${missing.length == 1 ? 'item' : 'items'} → groceries',
                kind: ButtonKind.primary,
                height: 46,
                fontSize: 14,
                onPressed: missing.isEmpty
                    ? null
                    : () {
                        final n = app.addWeekMissingToGroceries(_weekStart);
                        phoneToast(context, '$n added to groceries');
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayPill(BuildContext context, AppState app, DateTime day) {
    final t = context.tokens;
    final selected = app.dayOnly(day) == app.dayOnly(_day);
    final isToday = app.dayOnly(day) == app.dayOnly(DateTime.now());

    return GestureDetector(
      onTap: () => setState(() => _day = day),
      child: Container(
        width: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? t.accent.withValues(alpha: 0.14) : null,
          borderRadius: t.brContainer,
          border: Border.fromBorderSide(
            BorderSide(color: selected ? t.accent : Colors.transparent),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('EEE').format(day),
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11,
                color: selected ? t.accent : t.textMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('d').format(day),
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 15,
                color: selected
                    ? t.accent
                    : isToday
                        ? t.textStrong
                        : t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slot(BuildContext context, AppState app, MealSlot slot) {
    final t = context.tokens;
    final entry = app.planAt(_day, slot);
    final recipe = entry == null ? null : app.recipe(entry.recipeId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 7, left: 2),
            child: SectionLabel(slot.label),
          ),
          if (recipe == null)
            // A thin drop target, not an empty card demanding to be filled.
            InkWell(
              onTap: () => _fillSlot(context, slot),
              borderRadius: t.brContainer,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: t.brContainer,
                  border: Border.fromBorderSide(BorderSide(color: t.divider)),
                ),
                child: Center(
                  child: Icon(Icons.add, size: 17, color: t.textFaint),
                ),
              ),
            )
          else
            _filled(context, app, recipe, slot),
        ],
      ),
    );
  }

  Widget _filled(
    BuildContext context,
    AppState app,
    Recipe recipe,
    MealSlot slot,
  ) {
    final t = context.tokens;
    final per = app.macros.forRecipe(recipe).perServing;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.brContainer,
        boxShadow: t.shadowSm,
      ),
      child: InkWell(
        borderRadius: t.brContainer,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileRecipePage(recipeId: recipe.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 14.5,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${per.calories.round()} cal · '
                      '${per.protein.round()}g protein',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11.5,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 17, color: t.textFaint),
                onPressed: () => app.clearPlan(_day, slot),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The ＋ on an empty slot lists what fits: the slot's own meal type first
  /// with anything missing named, then everything cookable now whatever meal
  /// it was filed under, and a note when a recipe is already on the plan that
  /// week.
  Future<void> _fillSlot(BuildContext context, MealSlot slot) async {
    final app = context.read<AppState>();
    final cov = app.coverage;

    // Which meal type this slot corresponds to, matched by name.
    final slotType = app.mealTypes
        .where((m) => m.name.toLowerCase().startsWith(
              slot.label.toLowerCase().replaceAll('snack', 'snack'),
            ))
        .firstOrNull;

    final alreadyThisWeek = <String, String>{};
    for (var i = 0; i < 7; i++) {
      final day = _weekStart.add(Duration(days: i));
      for (final s in MealSlot.values) {
        final e = app.planAt(day, s);
        if (e != null) {
          alreadyThisWeek[e.recipeId] =
              '${DateFormat('EEE').format(day)} ${s.label.toLowerCase()}';
        }
      }
    }

    final filedHere = <Recipe>[];
    final cookableNow = <Recipe>[];
    for (final r in app.library.recipes) {
      if (slotType != null && r.mealTypeId == slotType.id) {
        filedHere.add(r);
      } else if (cov.summarise(r).missing.isEmpty) {
        cookableNow.add(r);
      }
    }

    if (!context.mounted) return;

    await showPhoneSheet<void>(
      context,
      title: 'Plan ${DateFormat('EEEE').format(_day)} '
          '${slot.label.toLowerCase()}',
      subtitle: '${DateFormat('EEE d MMM').format(_day)} · '
          '${app.dayTotals(_day).calories.round()} cal · '
          '${app.dayTotals(_day).protein.round()}g planned so far',
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          if (filedHere.isNotEmpty)
            _sheetHeading(context, 'Filed as ${slot.label.toLowerCase()}'),
          for (final r in filedHere)
            _option(context, sheetContext, app, cov, r,
                alreadyThisWeek[r.id], slot),
          if (cookableNow.isNotEmpty) _sheetHeading(context, 'Cook now'),
          for (final r in cookableNow.take(8))
            _option(context, sheetContext, app, cov, r,
                alreadyThisWeek[r.id], slot),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              'Nothing here? Suggestions can look at what the pantry covers.',
              style: TextStyle(
                fontFamily: context.tokens.bodyFamily,
                fontSize: 12,
                color: context.tokens.textFaint,
              ),
            ),
          ),
          SheetRow(
            icon: Icons.close,
            title: 'Leave it unplanned',
            onTap: () => Navigator.of(sheetContext).pop(),
          ),
        ],
      ),
    );
  }

  Widget _sheetHeading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: SectionLabel(text),
      );

  Widget _option(
    BuildContext context,
    BuildContext sheetContext,
    AppState app,
    dynamic cov,
    Recipe recipe,
    String? alreadyOn,
    MealSlot slot,
  ) {
    final summary = app.coverage.summarise(recipe);
    final per = app.macros.forRecipe(recipe).perServing;
    final type = app.mealType(recipe.mealTypeId);

    return SheetRow(
      icon: summary.missing.isEmpty
          ? Icons.check_circle_outline
          : Icons.remove_shopping_cart_outlined,
      title: recipe.title,
      detail: [
        '${per.calories.round()} cal',
        if (summary.missing.isEmpty)
          'everything in your pantry'
        else
          // Anything missing is named, not just counted.
          'missing ${summary.missing.map((m) => m.ingredient.name).join(', ')}',
        if (alreadyOn != null) 'already planned $alreadyOn',
      ].join(' · '),
      trailing: type == null ? null : Tag(type.name, dense: true),
      onTap: () {
        app.setPlan(_day, slot, recipe.id);
        Navigator.of(sheetContext).pop();
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
