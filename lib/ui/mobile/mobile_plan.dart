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
/// same figures, drawn from the same calculated macros. The desktop drags a
/// meal to another cell to move it, or onto a filled one to swap; here the
/// meal's menu does both, within the week on screen, as the grid does.
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
          // Room for the day, its number and today's dot.
          height: 72,
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
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous week',
                icon: Icon(Icons.chevron_left, color: t.textSecondary),
                onPressed: () => setState(
                  () => _day = _day.subtract(const Duration(days: 7)),
                ),
              ),
              Expanded(
                child: Text(
                  '${DateFormat('EEEE d MMMM').format(_day)} · '
                  '${totals.calories.round()} cal · '
                  '${totals.protein.round()}g',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12.5,
                    color: t.textMuted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next week',
                icon: Icon(Icons.chevron_right, color: t.textSecondary),
                onPressed: () =>
                    setState(() => _day = _day.add(const Duration(days: 7))),
              ),
            ],
          ),
        ),
        if (!_isThisWeek(app))
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                final now = DateTime.now();
                _day = DateTime(now.year, now.month, now.day);
              }),
              child: Text(
                'Back to today',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  color: t.accent,
                ),
              ),
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

  bool _isThisWeek(AppState app) {
    final today = app.dayOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return app.dayOnly(_weekStart) == monday;
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
            // Today is marked whether or not it is the day being looked at:
            // a slightly brighter number said "today" only next to the
            // others, and the strip scrolls a week at a time now.
            const SizedBox(height: 2),
            Container(
              key: isToday ? const Key('today-marker') : null,
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday ? t.accent : Colors.transparent,
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
                tooltip: 'Move or remove',
                icon: Icon(Icons.more_horiz, size: 19, color: t.textMuted),
                onPressed: () => _mealMenu(context, app, recipe, slot),
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
        .where(
          (m) => m.name.toLowerCase().startsWith(
            slot.label.toLowerCase().replaceAll('snack', 'snack'),
          ),
        )
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
      title:
          'Plan ${DateFormat('EEEE').format(_day)} '
          '${slot.label.toLowerCase()}',
      subtitle:
          '${DateFormat('EEE d MMM').format(_day)} · '
          '${app.dayTotals(_day).calories.round()} cal · '
          '${app.dayTotals(_day).protein.round()}g planned so far',
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          if (filedHere.isNotEmpty)
            _sheetHeading(context, 'Filed as ${slot.label.toLowerCase()}'),
          for (final r in filedHere)
            _option(
              context,
              sheetContext,
              app,
              cov,
              r,
              alreadyThisWeek[r.id],
              slot,
            ),
          if (cookableNow.isNotEmpty) _sheetHeading(context, 'Cook now'),
          for (final r in cookableNow.take(8))
            _option(
              context,
              sheetContext,
              app,
              cov,
              r,
              alreadyThisWeek[r.id],
              slot,
            ),
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

  // ── Moving a meal ───────────────────────────────────────────────────────

  Future<void> _mealMenu(
    BuildContext context,
    AppState app,
    Recipe recipe,
    MealSlot slot,
  ) async {
    final choice = await showPhoneSheet<String>(
      context,
      title: recipe.title,
      subtitle:
          '${DateFormat('EEEE').format(_day)} ${slot.label.toLowerCase()}',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetRow(
            icon: Icons.swap_vert,
            title: 'Move or swap…',
            detail: 'Another day or meal this week',
            onTap: () => Navigator.of(sheet).pop('move'),
          ),
          SheetRow(
            icon: Icons.close,
            title: 'Remove from plan',
            detail: 'The recipe stays in your library',
            accent: true,
            onTap: () => Navigator.of(sheet).pop('remove'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == 'remove') {
      app.clearPlan(_day, slot);
    } else if (choice == 'move') {
      await _moveSheet(context, app, recipe, slot);
    }
  }

  /// Picks where in the week a meal goes. An empty slot is a move; a filled
  /// one is a swap, and says so with the recipe it would trade places with.
  Future<void> _moveSheet(
    BuildContext context,
    AppState app,
    Recipe recipe,
    MealSlot fromSlot,
  ) async {
    final fromDay = _day;
    var target = _day;

    final picked = await showPhoneSheet<({DateTime day, MealSlot slot})>(
      context,
      title: 'Move ${recipe.title}',
      subtitle:
          'From ${DateFormat('EEEE').format(fromDay)} '
          '${fromSlot.label.toLowerCase()}',
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          final t = sheet.tokens;
          return ListView(
            shrinkWrap: true,
            children: [
              SizedBox(
                height: 62,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (var i = 0; i < 7; i++)
                      _targetDay(
                        sheet,
                        app,
                        _weekStart.add(Duration(days: i)),
                        selected:
                            app.dayOnly(_weekStart.add(Duration(days: i))) ==
                            app.dayOnly(target),
                        onTap: () => setSheet(
                          () => target = _weekStart.add(Duration(days: i)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              for (final slot in MealSlot.values)
                () {
                  final here =
                      app.dayOnly(target) == app.dayOnly(fromDay) &&
                      slot == fromSlot;
                  final entry = app.planAt(target, slot);
                  final occupant = entry == null
                      ? null
                      : app.recipe(entry.recipeId);
                  return Opacity(
                    opacity: here ? 0.45 : 1,
                    child: SheetRow(
                      icon: here
                          ? Icons.radio_button_checked
                          : occupant == null
                          ? Icons.arrow_forward
                          : Icons.swap_horiz,
                      title: slot.label,
                      detail: here
                          ? 'Where it is now'
                          : occupant == null
                          ? 'Empty — move it here'
                          : 'Swap with ${occupant.title}',
                      trailing: here
                          ? null
                          : Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: t.textFaint,
                            ),
                      onTap: here
                          ? null
                          : () => Navigator.of(
                              sheet,
                            ).pop((day: target, slot: slot)),
                    ),
                  );
                }(),
            ],
          );
        },
      ),
    );
    if (picked == null || !context.mounted) return;

    final swapped = app.planAt(picked.day, picked.slot) != null;
    app.movePlan(fromDay, fromSlot, picked.day, picked.slot);
    final where =
        '${DateFormat('EEEE').format(picked.day)} '
        '${picked.slot.label.toLowerCase()}';
    phoneToast(context, swapped ? 'Swapped with $where' : 'Moved to $where');
  }

  Widget _targetDay(
    BuildContext context,
    AppState app,
    DateTime day, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? t.accent.withValues(alpha: 0.14) : null,
          borderRadius: t.brContainer,
          border: Border.fromBorderSide(
            BorderSide(color: selected ? t.accent : t.divider),
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
                color: selected ? t.accent : t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
