import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/macros.dart';
import '../../domain/units.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// The commands cook mode understands. The same set everywhere — the desktop
/// mirrors them on the keyboard, the phone hears them.
enum CookCommand {
  next('next'),
  back('back'),
  repeat('repeat'),
  startTimer('start a timer'),
  stop('stop');

  const CookCommand(this.spoken);
  final String spoken;
}

abstract final class CookMode {
  /// True while a cook session is on screen.
  ///
  /// A recipe shared into the app mid-cook must not throw the user out of the
  /// kitchen, so the share intake waits on this.
  static bool get isActive => _active;
  static bool _active = false;

  /// Start cooking checks the pantry first. The missing item is named with
  /// where it is used, and Cook anyway is always offered — nothing here
  /// refuses to start.
  static Future<void> start(BuildContext context, String recipeId) async {
    final app = context.read<AppState>();
    final recipe = app.recipe(recipeId);
    if (recipe == null) return;

    final missing = app.coverage.summarise(recipe).missing;
    if (missing.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => _PantryCheckDialog(recipe: recipe, missing: missing),
      );
      if (proceed != true || !context.mounted) return;
    }

    if (!context.mounted) return;
    _active = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (_, _, _) => CookModeScreen(recipeId: recipeId),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } finally {
      _active = false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Pantry check
// ═══════════════════════════════════════════════════════════════════════════

class _PantryCheckDialog extends StatelessWidget {
  const _PantryCheckDialog({required this.recipe, required this.missing});

  final Recipe recipe;
  final List<CoverageResult> missing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.read<AppState>();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        padding: EdgeInsets.all(t.space(4)),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: t.brLarge,
          boxShadow: t.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              missing.length == 1
                  ? 'One thing is missing'
                  : '${missing.length} things are missing',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: t.space(2)),
            Text(
              'You can still cook — this is only so nothing surprises you '
              'halfway through.',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12.5,
                color: t.textMuted,
                height: 1.5,
              ),
            ),
            SizedBox(height: t.space(4)),
            for (final m in missing)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.priority_high, size: 15, color: t.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.ingredient.name,
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 13,
                              color: t.text,
                            ),
                          ),
                          Text(
                            _usedIn(recipe, m.ingredient),
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 11,
                              color: t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppButton(
                      'Add to groceries',
                      fontSize: 11,
                      height: 26,
                      onPressed: () {
                        // Adding to groceries leaves the recipe open.
                        app.addGrocery(
                          m.ingredient.name,
                          quantity: m.ingredient.quantity == null
                              ? m.ingredient.unit
                              : '${formatAmount(m.ingredient.quantity)} '
                                      '${m.ingredient.unit}'
                                  .trim(),
                          source: recipe.title,
                        );
                      },
                    ),
                  ],
                ),
              ),
            SizedBox(height: t.space(4)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  'Not now',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 8),
                AppButton(
                  'Cook anyway',
                  kind: ButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _usedIn(Recipe recipe, Ingredient line) {
    final component = recipe.components
        .where((c) => c.id == line.componentId)
        .firstOrNull;
    final steps = recipe.orderedSteps;
    final stepNumbers = <int>[];
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].componentId != line.componentId) continue;
      if (steps[i].text.toLowerCase().contains(
            line.name.split(',').first.toLowerCase(),
          )) {
        stepNumbers.add(i + 1);
      }
    }
    final where = component == null ? '' : 'in ${component.name}';
    if (stepNumbers.isEmpty) return where;
    return '$where · step ${stepNumbers.join(', ')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Cook mode
// ═══════════════════════════════════════════════════════════════════════════

class CookModeScreen extends StatefulWidget {
  const CookModeScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends State<CookModeScreen> {
  final _focus = FocusNode();
  int _step = 0;

  /// Timers belong to the step that started them and keep running as the user
  /// moves on.
  final _timers = <_CookTimer>[];
  Timer? _ticker;

  /// Every heard command shows a confirmation card naming what it heard and
  /// what it did, so a misheard word is obvious immediately.
  ({String heard, String did})? _lastCommand;
  Timer? _commandFade;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timers.isNotEmpty) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _commandFade?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _run(CookCommand command, {String? heard}) {
    final recipe = context.read<AppState>().recipe(widget.recipeId);
    if (recipe == null) return;
    final steps = recipe.orderedSteps;
    var did = '';

    switch (command) {
      case CookCommand.next:
        if (_step < steps.length - 1) {
          setState(() => _step++);
          did = 'moved to step ${_step + 1}';
        } else {
          did = 'already on the last step';
        }
      case CookCommand.back:
        if (_step > 0) {
          setState(() => _step--);
          did = 'moved to step ${_step + 1}';
        } else {
          did = 'already on the first step';
        }
      case CookCommand.repeat:
        did = 'repeated step ${_step + 1}';
      case CookCommand.startTimer:
        _startTimer(steps[_step], recipe);
        did = 'started a timer on step ${_step + 1}';
      case CookCommand.stop:
        _leave();
        return;
    }

    _showCommand(heard ?? command.spoken, did);
  }

  void _showCommand(String heard, String did) {
    _commandFade?.cancel();
    setState(() => _lastCommand = (heard: heard, did: did));
    _commandFade = Timer(
      const Duration(seconds: 4),
      () => mounted ? setState(() => _lastCommand = null) : null,
    );
  }

  void _startTimer(RecipeStep step, Recipe recipe) {
    final minutes = step.timerMinutes ?? _guessMinutes(step.text) ?? 5;
    setState(() {
      _timers.add(_CookTimer(
        stepNumber: recipe.orderedSteps.indexOf(step) + 1,
        endsAt: DateTime.now().add(Duration(minutes: minutes)),
        minutes: minutes,
      ));
    });
  }

  /// Pulls "20 minutes" or "three minutes a side" out of the step so the timer
  /// starts at something sensible rather than a fixed default.
  int? _guessMinutes(String text) {
    final digits = RegExp(r'(\d+)\s*(?:minute|min)').firstMatch(text);
    if (digits != null) return int.tryParse(digits.group(1)!);
    const words = {
      'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
      'fifteen': 15, 'twenty': 20, 'thirty': 30,
    };
    for (final entry in words.entries) {
      if (RegExp('${entry.key}\\s*(?:minute|min)').hasMatch(text)) {
        return entry.value;
      }
    }
    return null;
  }

  void _leave() {
    // Leaving cook mode returns to the recipe at the step reached.
    context.read<AppState>().markCooked(widget.recipeId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final recipe = app.recipe(widget.recipeId);
    if (recipe == null) return const SizedBox.shrink();

    final steps = recipe.orderedSteps;
    if (steps.isEmpty) {
      return Scaffold(
        backgroundColor: t.ground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This recipe has no steps yet.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              AppButton('Back', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      );
    }

    final step = steps[_step];
    final component = recipe.componentOf(step);
    final lines = recipe.ingredientsOf(step.componentId);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // Desktop mirrors the voice commands on the keyboard.
        switch (event.logicalKey) {
          case LogicalKeyboardKey.space:
          case LogicalKeyboardKey.arrowRight:
            _run(CookCommand.next, heard: 'space / →');
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowLeft:
            _run(CookCommand.back, heard: '←');
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyT:
            _run(CookCommand.startTimer, heard: 'T');
            return KeyEventResult.handled;
          case LogicalKeyboardKey.escape:
            _leave();
            return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: t.ground,
        body: Row(
          children: [
            _stepList(context, recipe, steps),
            Expanded(
              child: Column(
                children: [
                  _header(context, recipe, steps.length),
                  Expanded(
                    child: _stepCard(context, step, component, lines, recipe),
                  ),
                  _controls(context, steps.length),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step list down the side ─────────────────────────────────────────────

  Widget _stepList(
    BuildContext context,
    Recipe recipe,
    List<RecipeStep> steps,
  ) {
    final t = context.tokens;
    return Container(
      width: 260,
      color: t.chrome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
            child: Text(
              recipe.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final c in recipe.orderedComponents) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                    child: SectionLabel(c.name, color: t.accentText, size: 10),
                  ),
                  for (final s in recipe.stepsOf(c.id))
                    _stepListRow(context, steps.indexOf(s), s),
                ],
              ],
            ),
          ),
          if (_timers.isNotEmpty) _timerPanel(context),
        ],
      ),
    );
  }

  Widget _stepListRow(BuildContext context, int index, RecipeStep step) {
    final t = context.tokens;
    final current = index == _step;
    final done = index < _step;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: HoverRow(
        borderRadius: t.brContainer,
        onTap: () => setState(() => _step = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: current ? t.accent.withValues(alpha: 0.14) : null,
            borderRadius: t.brContainer,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: done
                    ? Icon(Icons.check, size: 14, color: t.textFaint)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 12,
                          color: current ? t.accent : t.textMuted,
                        ),
                      ),
              ),
              Expanded(
                child: Text(
                  step.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12,
                    height: 1.4,
                    color: current
                        ? t.text
                        : done
                            ? t.textFaint
                            : t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timerPanel(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('Timers'),
          const SizedBox(height: 10),
          for (final timer in _timers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    timer.done ? Icons.notifications_active : Icons.timer,
                    size: 15,
                    color: timer.done ? t.accent : t.textMuted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timer.label,
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 15,
                            color: timer.done ? t.accent : t.text,
                          ),
                        ),
                        Text(
                          'step ${timer.stepNumber}',
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 10.5,
                            color: t.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.close,
                    size: 22,
                    iconSize: 12,
                    bordered: false,
                    onPressed: () => setState(() => _timers.remove(timer)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Header, card, controls ──────────────────────────────────────────────

  Widget _header(BuildContext context, Recipe recipe, int total) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Row(
        children: [
          Text(
            'Step ${_step + 1} of $total',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 14,
              color: t.textMuted,
            ),
          ),
          const Spacer(),
          if (_lastCommand != null) _commandCard(context),
          const Spacer(),
          AppButton('Leave cook mode', onPressed: _leave),
        ],
      ),
    );
  }

  Widget _commandCard(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.brContainer,
        border: Border.fromBorderSide(BorderSide(color: t.accent)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, size: 15, color: t.accent),
          const SizedBox(width: 9),
          Text(
            'Heard “${_lastCommand!.heard}” — ${_lastCommand!.did}',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 12.5,
              color: t.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCard(
    BuildContext context,
    RecipeStep step,
    RecipeComponent? component,
    List<Ingredient> lines,
    Recipe recipe,
  ) {
    final t = context.tokens;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
          child: Container(
            padding: const EdgeInsets.all(34),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: t.brLarge,
              // Nocturne lifts the card off the ground with an accent line and
              // a soft glow. On cream that does almost nothing, so Organic
              // leans on the surface fill and a divider instead.
              border: t.cookModeGlow
                  ? Border(left: BorderSide(color: t.accent, width: 3))
                  : Border.fromBorderSide(BorderSide(color: t.divider)),
              boxShadow: t.cookModeGlow ? t.shadowMd : t.shadowSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (component != null)
                  SectionLabel(component.name, color: t.accentText, size: 12),
                const SizedBox(height: 18),
                // Arm's-length type.
                Text(
                  step.text,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 30,
                    height: 1.45,
                    color: t.text,
                  ),
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  Container(height: 1, color: t.divider),
                  const SizedBox(height: 18),
                  // The step's own ingredients, repeated so nobody has to
                  // scroll back.
                  SectionLabel('For this step'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 22,
                    runSpacing: 10,
                    children: [
                      for (final line in lines)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              line.quantity == null
                                  ? line.unit
                                  : '${formatAmount(line.quantity)} ${line.unit}'
                                      .trim(),
                              style: TextStyle(
                                fontFamily: t.bodyFamily,
                                fontSize: 17,
                                color: t.accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              line.name,
                              style: TextStyle(
                                fontFamily: t.bodyFamily,
                                fontSize: 17,
                                color: t.textSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, int total) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 16, 40, 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppButton(
                'Back',
                icon: Icons.arrow_back,
                fontSize: 15,
                height: 48,
                onPressed:
                    _step > 0 ? () => _run(CookCommand.back, heard: '←') : null,
              ),
              const SizedBox(width: 12),
              AppButton(
                'Start a timer',
                icon: Icons.timer_outlined,
                fontSize: 15,
                height: 48,
                onPressed: () => _run(CookCommand.startTimer, heard: 'T'),
              ),
              const SizedBox(width: 12),
              AppButton(
                _step == total - 1 ? 'Finish' : 'Next',
                kind: ButtonKind.primary,
                icon: Icons.arrow_forward,
                fontSize: 15,
                height: 48,
                onPressed: _step == total - 1
                    ? _leave
                    : () => _run(CookCommand.next, heard: 'space'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Space or → next · ← back · T timer · Esc leave.  '
            'Voice: ${CookCommand.values.map((c) => c.spoken).join(', ')}.',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11.5,
              color: t.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _CookTimer {
  _CookTimer({
    required this.stepNumber,
    required this.endsAt,
    required this.minutes,
  });

  final int stepNumber;
  final DateTime endsAt;
  final int minutes;

  Duration get remaining => endsAt.difference(DateTime.now());
  bool get done => remaining.isNegative;

  String get label {
    if (done) return 'done';
    final d = remaining;
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
