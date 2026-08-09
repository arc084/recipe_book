import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// Seven days across, four slots down.
///
/// Nothing is planned by the app; the grid only adds up what is put in it.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late DateTime _weekStart;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _weekStart = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DateTime> get _days =>
      [for (var i = 0; i < 7; i++) _weekStart.add(Duration(days: i))];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Row(
      children: [
        Expanded(child: _grid(context, app)),
        _rail(context, app),
      ],
    );
  }

  // ── Grid ────────────────────────────────────────────────────────────────

  Widget _grid(BuildContext context, AppState app) {
    final t = context.tokens;
    final missing = app.missingForWeek(_weekStart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Meal plan',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${DateFormat('d MMM').format(_weekStart)} – '
                    '${DateFormat('d MMM').format(_weekStart.add(const Duration(days: 6)))}',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              AppIconButton(
                icon: Icons.chevron_left,
                size: 28,
                onPressed: () => setState(
                  () => _weekStart =
                      _weekStart.subtract(const Duration(days: 7)),
                ),
              ),
              const SizedBox(width: 6),
              AppIconButton(
                icon: Icons.chevron_right,
                size: 28,
                onPressed: () => setState(
                  () => _weekStart = _weekStart.add(const Duration(days: 7)),
                ),
              ),
              const Spacer(),
              // The one action on this screen, counted before it is pressed.
              AppButton(
                missing.isEmpty
                    ? 'Nothing missing this week'
                    : 'Add ${missing.length} missing '
                        '${missing.length == 1 ? 'item' : 'items'} to groceries',
                kind: ButtonKind.primary,
                onPressed: missing.isEmpty
                    ? null
                    : () {
                        final n = app.addWeekMissingToGroceries(_weekStart);
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(SnackBar(
                            content: Text('$n added to groceries'),
                            backgroundColor: t.surface,
                            behavior: SnackBarBehavior.floating,
                            width: 320,
                          ));
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 86),
                    for (final day in _days)
                      Expanded(child: _dayHeader(context, app, day)),
                  ],
                ),
                const SizedBox(height: 10),
                for (final slot in MealSlot.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          // Wide enough that "Breakfast" does not wrap once
                          // the label's tracking is applied.
                          width: 86,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14, right: 10),
                            child: SectionLabel(slot.label, size: 10),
                          ),
                        ),
                        for (final day in _days)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _slot(context, app, day, slot),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayHeader(BuildContext context, AppState app, DateTime day) {
    final t = context.tokens;
    final totals = app.dayTotals(day);
    final isToday = app.dayOnly(DateTime.now()) == app.dayOnly(day);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                DateFormat('EEE').format(day),
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  color: isToday ? t.accent : t.textSecondary,
                  fontVariations: [
                    FontVariation('wght', isToday ? 600 : 400),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                DateFormat('d').format(day),
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  color: isToday ? t.accent : t.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Summed from the same calculated macros the recipe screens show.
          Text(
            totals.calories == 0
                ? '—'
                : '${totals.calories.round()} cal · '
                    '${totals.protein.round()}g',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 10.5,
              color: t.textFaint,
            ),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: isToday ? t.accent : t.divider),
        ],
      ),
    );
  }

  Widget _slot(
    BuildContext context,
    AppState app,
    DateTime day,
    MealSlot slot,
  ) {
    final t = context.tokens;
    final entry = app.planAt(day, slot);
    final recipe = entry == null ? null : app.recipe(entry.recipeId);

    return DragTarget<_PlanDrag>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        final data = d.data;
        if (data.fromDate == null || data.fromSlot == null) {
          // Dragging from the rail copies the recipe in and leaves the
          // library alone.
          app.setPlan(day, slot, data.recipeId);
        } else {
          // Dropping onto a filled slot swaps the two.
          app.movePlan(data.fromDate!, data.fromSlot!, day, slot);
        }
      },
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;

        if (recipe == null) {
          // Empty slots are thin drop targets, not empty cards demanding to
          // be filled.
          return Container(
            height: active ? 62 : 26,
            decoration: BoxDecoration(
              color: active ? t.accent.withValues(alpha: 0.10) : null,
              borderRadius: t.brContainer,
              border: Border.fromBorderSide(
                BorderSide(
                  color: active ? t.accent : t.divider,
                  style: active ? BorderStyle.solid : BorderStyle.solid,
                ),
              ),
            ),
            child: Center(
              child: Icon(
                Icons.add,
                size: 13,
                color: active ? t.accent : t.textFaint.withValues(alpha: 0.5),
              ),
            ),
          );
        }

        final card = _planCard(context, app, recipe, day, slot, active);
        return Draggable<_PlanDrag>(
          data: _PlanDrag(
            recipeId: recipe.id,
            fromDate: day,
            fromSlot: slot,
          ),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 150, child: card),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: card),
          child: card,
        );
      },
    );
  }

  Widget _planCard(
    BuildContext context,
    AppState app,
    Recipe recipe,
    DateTime day,
    MealSlot slot,
    bool active,
  ) {
    final t = context.tokens;
    final per = app.macros.forRecipe(recipe).perServing;

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.brContainer,
        boxShadow: active ? t.shadowMd : t.shadowSm,
        border: active
            ? Border.fromBorderSide(BorderSide(color: t.accent))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () =>
                    context.read<NavController>().openRecipe(recipe.id),
                child: Text(
                  recipe.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11.5,
                    height: 1.3,
                    color: t.text,
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${per.calories.round()} cal',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 10,
                    color: t.textMuted,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => app.clearPlan(day, slot),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.close, size: 12, color: t.textFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Rail ────────────────────────────────────────────────────────────────

  Widget _rail(BuildContext context, AppState app) {
    final t = context.tokens;
    final q = _query.trim().toLowerCase();
    final recipes = app.library.recipes
        .where((r) => q.isEmpty || r.title.toLowerCase().contains(q))
        .toList();

    // A recipe already on the plan this week is worth flagging.
    final onPlan = <String>{
      for (var i = 0; i < 7; i++)
        for (final slot in MealSlot.values)
          if (app.planAt(_weekStart.add(Duration(days: i)), slot) != null)
            app.planAt(_weekStart.add(Duration(days: i)), slot)!.recipeId,
    };

    return Container(
      width: 262,
      decoration: BoxDecoration(
        color: t.chrome,
        border: Border(left: BorderSide(color: t.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Drag one in',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Dragging from here copies the recipe onto the plan and '
                  'leaves your library alone.',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11,
                    height: 1.45,
                    color: t.textFaint,
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _search,
                  hint: 'Search recipes',
                  icon: Icons.search,
                  fontSize: 12.5,
                  height: 32,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: recipes.length,
              itemBuilder: (context, i) =>
                  _railRow(context, app, recipes[i], onPlan),
            ),
          ),
        ],
      ),
    );
  }

  Widget _railRow(
    BuildContext context,
    AppState app,
    Recipe recipe,
    Set<String> onPlan,
  ) {
    final t = context.tokens;
    final per = app.macros.forRecipe(recipe).perServing;
    final missing = app.coverage.summarise(recipe).missing.length;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.brContainer,
        boxShadow: t.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  recipe.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12.5,
                    color: t.text,
                  ),
                ),
              ),
              if (onPlan.contains(recipe.id))
                Tooltip(
                  message: 'Already on the plan this week',
                  child: Icon(Icons.event_available, size: 13, color: t.accent),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            [
              '${per.calories.round()} cal',
              '${per.protein.round()}g protein',
              if (missing > 0) '$missing missing',
            ].join(' · '),
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 10.5,
              color: missing > 0 ? t.accent : t.textMuted,
            ),
          ),
        ],
      ),
    );

    return Draggable<_PlanDrag>(
      data: _PlanDrag(recipeId: recipe.id),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 200, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: card,
      ),
    );
  }
}

/// What is being dragged. A null [fromDate] means it came from the rail, so it
/// is a copy rather than a move.
class _PlanDrag {
  const _PlanDrag({required this.recipeId, this.fromDate, this.fromSlot});

  final String recipeId;
  final DateTime? fromDate;
  final MealSlot? fromSlot;
}
