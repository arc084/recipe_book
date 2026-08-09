import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/recipe_parser.dart';
import '../../domain/units.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// Import from web.
///
/// Three steps: get the link in, check what was read off the page, confirm how
/// each ingredient matches the pantry. **Nothing is written to the library
/// until the last step**, and discarding at any point leaves it untouched.
abstract final class ImportFlow {
  /// Step 1 runs as a dialog; steps 2–3 are full-window screens.
  static Future<void> start(BuildContext context) async {
    final source = await showDialog<_ImportSource>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );
    if (source == null || !context.mounted) return;

    final parsed = await _read(context, source);
    if (parsed == null || !context.mounted) return;

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => _ReviewScreen(parsed: parsed),
      ),
    );
  }

  static Future<ParsedRecipe?> _read(
    BuildContext context,
    _ImportSource source,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final String body;
      if (source.html != null) {
        body = source.html!;
      } else {
        final response = await http
            .get(Uri.parse(source.url!))
            .timeout(const Duration(seconds: 20));
        body = response.body;
      }

      final parsed = RecipeParser.parse(body, url: source.url);
      if (parsed == null) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Nothing on that page reads as a recipe.'),
          behavior: SnackBarBehavior.floating,
          width: 400,
        ));
        return null;
      }
      return parsed;
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not read that page. $e'),
        behavior: SnackBarBehavior.floating,
        width: 460,
      ));
      return null;
    }
  }
}

class _ImportSource {
  const _ImportSource({this.url, this.html});

  final String? url;

  /// A saved `.html` page dropped onto the dialog.
  final String? html;
}

// ═══════════════════════════════════════════════════════════════════════════
// Step 1 — get the link in
// ═══════════════════════════════════════════════════════════════════════════

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _controller = TextEditingController();

  /// The clipboard is offered by name rather than read silently.
  String? _clipboardUrl;
  bool _dragOver = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _peekClipboard();
  }

  Future<void> _peekClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    final uri = Uri.tryParse(text);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (mounted) setState(() => _clipboardUrl = text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();

    // Sites already imported from are listed because they parse reliably.
    final knownSites = <String>{
      for (final r in app.library.recipes)
        if (r.sourceUrl != null)
          Uri.tryParse(r.sourceUrl!)?.host.replaceFirst('www.', '') ?? '',
    }..removeWhere((s) => s.isEmpty);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragOver = true),
        onDragExited: (_) => setState(() => _dragOver = false),
        onDragDone: (detail) async {
          setState(() => _dragOver = false);
          final file = detail.files.firstOrNull;
          if (file == null) return;
          if (file.path.toLowerCase().endsWith('.html') ||
              file.path.toLowerCase().endsWith('.htm')) {
            final text = await file.readAsString();
            if (!context.mounted) return;
            Navigator.of(context).pop(_ImportSource(html: text));
          }
        },
        child: Container(
          width: 480,
          padding: EdgeInsets.all(t.space(4)),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: t.brLarge,
            boxShadow: t.shadowLg,
            border: _dragOver
                ? Border.fromBorderSide(BorderSide(color: t.accent, width: 2))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Import from web',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Nothing is saved until you have checked what was read off '
                'the page.',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12,
                  color: t.textMuted,
                ),
              ),
              SizedBox(height: t.space(4)),
              if (_clipboardUrl != null) ...[
                HoverRow(
                  borderRadius: t.brContainer,
                  onTap: () => Navigator.of(context)
                      .pop(_ImportSource(url: _clipboardUrl)),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: t.brContainer,
                      border: Border.fromBorderSide(
                        BorderSide(color: t.accent),
                      ),
                      color: t.accent.withValues(alpha: 0.08),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.content_paste, size: 16, color: t.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Use what is on your clipboard',
                                style: TextStyle(
                                  fontFamily: t.bodyFamily,
                                  fontSize: 12.5,
                                  color: t.text,
                                ),
                              ),
                              Text(
                                _clipboardUrl!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                SizedBox(height: t.space(3)),
              ],
              AppTextField(
                controller: _controller,
                hint: 'Paste a link',
                icon: Icons.link,
                autofocus: true,
                onSubmitted: (v) => v.trim().isEmpty
                    ? null
                    : Navigator.of(context).pop(_ImportSource(url: v.trim())),
              ),
              SizedBox(height: t.space(3)),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: t.brContainer,
                  border: Border.fromBorderSide(BorderSide(color: t.divider)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined,
                        size: 16, color: t.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Or drop a saved .html page onto this dialog.',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 12,
                          color: t.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (knownSites.isNotEmpty) ...[
                SizedBox(height: t.space(4)),
                Text(
                  'You have imported from these before, so they parse '
                  'reliably',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11,
                    color: t.textFaint,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final site in knownSites) Tag(site, dense: true),
                  ],
                ),
              ],
              SizedBox(height: t.space(4)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    _busy ? 'Reading…' : 'Read the page',
                    kind: ButtonKind.primary,
                    onPressed: _busy
                        ? null
                        : () {
                            final url = _controller.text.trim();
                            if (url.isEmpty) return;
                            setState(() => _busy = true);
                            Navigator.of(context)
                                .pop(_ImportSource(url: url));
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Step 2 — check what was read
// ═══════════════════════════════════════════════════════════════════════════

class _ReviewScreen extends StatefulWidget {
  const _ReviewScreen({required this.parsed});

  final ParsedRecipe parsed;

  @override
  State<_ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<_ReviewScreen> {
  late String _mealTypeId;

  @override
  void initState() {
    super.initState();
    _mealTypeId = context.read<AppState>().mealTypes.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final p = widget.parsed;

    return Scaffold(
      backgroundColor: t.ground,
      body: Column(
        children: [
          _StepHeader(
            step: 2,
            title: 'Check what was read',
            subtitle: 'Every field is writable — fix a mangled quantity here, '
                'before anything is saved.',
            onDiscard: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(30, 20, 30, 20),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Field(
                            label: 'Title',
                            value: p.title,
                            onChanged: (v) => p.title = v,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: _Field(
                            label: 'Servings',
                            value: '${p.servings ?? 4}',
                            onChanged: (v) => p.servings = int.tryParse(v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: _Field(
                            label: 'Minutes',
                            value: p.totalMinutes?.toString() ?? '',
                            onChanged: (v) => p.totalMinutes = int.tryParse(v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'Meal type',
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 11,
                            color: t.textMuted,
                          ),
                        ),
                        const SizedBox(width: 10),
                        for (final type in app.mealTypes) ...[
                          Tag(
                            type.name,
                            style: _mealTypeId == type.id
                                ? TagStyle.accent
                                : TagStyle.outline,
                            onTap: () =>
                                setState(() => _mealTypeId = type.id),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                    if (p.listedCalories != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          borderRadius: t.brContainer,
                          border: Border.fromBorderSide(
                            BorderSide(color: t.divider),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: t.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'The page says ${p.listedCalories!.round()} '
                                'calories. That figure is not stored — the '
                                'total calculated from your pantry replaces '
                                'it once this is saved.',
                                style: TextStyle(
                                  fontFamily: t.bodyFamily,
                                  fontSize: 12,
                                  height: 1.5,
                                  color: t.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SectionLabel('Ingredients'),
                    const SizedBox(height: 10),
                    Panel(
                      clip: true,
                      child: Column(
                        children: [
                          for (var i = 0; i < p.ingredients.length; i++)
                            _ingredientRow(context, i),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    SectionLabel('Method'),
                    const SizedBox(height: 10),
                    for (var i = 0; i < p.steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 23,
                              height: 23,
                              margin: const EdgeInsets.only(top: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(
                                  BorderSide(color: t.accent),
                                ),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontFamily: t.bodyFamily,
                                  fontSize: 11.5,
                                  color: t.accent,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Field(
                                value: p.steps[i],
                                multiline: true,
                                onChanged: (v) => p.steps[i] = v,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _StepFooter(
            note: p.uncertainIngredients.isEmpty
                ? 'Everything read cleanly.'
                : '${p.uncertainIngredients.length} '
                    '${p.uncertainIngredients.length == 1 ? 'line was' : 'lines were'}'
                    ' hard to read: '
                    '${p.uncertainIngredients.map((i) => p.ingredients[i].raw).join(' · ')}',
            highlight: p.uncertainIngredients.isNotEmpty,
            primaryLabel: 'Match to pantry',
            onPrimary: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _MatchScreen(
                  parsed: p,
                  mealTypeId: _mealTypeId,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ingredientRow(BuildContext context, int index) {
    final t = context.tokens;
    final p = widget.parsed;
    final line = p.ingredients[index];
    // Lines the parser was unsure of are outlined and named in the footer.
    final uncertain = p.uncertainIngredients.contains(index);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: index == 0 ? Colors.transparent : t.divider),
        ),
        color: uncertain ? t.accent.withValues(alpha: 0.08) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: _Field(
              value: formatAmount(line.quantity),
              hint: 'qty',
              onChanged: (v) => line.quantity = double.tryParse(v.trim()),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: _Field(
              value: line.unit,
              hint: 'unit',
              onChanged: (v) => line.unit = v.trim(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Field(
              value: line.name,
              hint: 'ingredient',
              onChanged: (v) => line.name = v,
            ),
          ),
          if (uncertain)
            Tooltip(
              message: 'The page wrote this as “${line.raw}”',
              child: Icon(Icons.help_outline, size: 15, color: t.accent),
            ),
          AppIconButton(
            icon: Icons.close,
            size: 24,
            iconSize: 13,
            bordered: false,
            onPressed: () => setState(() {
              p.ingredients.removeAt(index);
              p.uncertainIngredients
                ..remove(index)
                ..removeWhere((i) => i >= p.ingredients.length);
            }),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Step 3 — match to the pantry. Only this step commits.
// ═══════════════════════════════════════════════════════════════════════════

enum _MatchKind { linked, branded, unmatched }

class _Match {
  _Match({required this.line, required this.kind, this.pantryItemId});

  final ParsedIngredient line;
  _MatchKind kind;
  String? pantryItemId;
}

class _MatchScreen extends StatefulWidget {
  const _MatchScreen({required this.parsed, required this.mealTypeId});

  final ParsedRecipe parsed;
  final String mealTypeId;

  @override
  State<_MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<_MatchScreen> {
  late final List<_Match> _matches;

  /// On by default: later imports using the same names link without asking.
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _matches = [
      for (final line in widget.parsed.ingredients) _initial(app, line),
    ];
  }

  _Match _initial(AppState app, ParsedIngredient line) {
    // A loose name links to the user's item and inherits its macros.
    final match = app.pantry.items
        .where((p) => p.matchesName(line.name))
        .firstOrNull;
    if (match != null) {
      return _Match(
        line: line,
        kind: _MatchKind.linked,
        pantryItemId: match.id,
      );
    }

    // A branded name stays separate as its own ingredient.
    if (_looksBranded(line.name)) {
      return _Match(line: line, kind: _MatchKind.branded);
    }

    // A softer match on containment, so "chopped tomatoes, tinned" still finds
    // "canned tomatoes" without claiming certainty.
    final loose = app.pantry.items.where((p) {
      final name = line.name.toLowerCase();
      return p.allNames.any((n) => name.contains(n.toLowerCase()));
    }).firstOrNull;

    if (loose != null) {
      return _Match(
        line: line,
        kind: _MatchKind.linked,
        pantryItemId: loose.id,
      );
    }

    return _Match(line: line, kind: _MatchKind.unmatched);
  }

  /// A capitalised word mid-name usually means a brand.
  static bool _looksBranded(String name) {
    final words = name.split(RegExp(r'\s+'));
    for (var i = 1; i < words.length; i++) {
      final w = words[i];
      if (w.length > 2 && w[0] == w[0].toUpperCase() && w[0] != w[0].toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();

    final linked = _matches.where((m) => m.kind == _MatchKind.linked).length;
    final unmatched =
        _matches.where((m) => m.kind == _MatchKind.unmatched).length;

    return Scaffold(
      backgroundColor: t.ground,
      body: Column(
        children: [
          _StepHeader(
            step: 3,
            title: 'Match to your pantry',
            subtitle: 'Linked ingredients inherit that item’s macros. Nothing '
                'is saved until you press Save.',
            onDiscard: () => Navigator.of(context)
              ..pop()
              ..pop(),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(30, 20, 30, 20),
                  children: [
                    Panel(
                      clip: true,
                      child: Column(
                        children: [
                          for (var i = 0; i < _matches.length; i++)
                            _matchRow(context, app, _matches[i], i > 0),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _Check(
                          value: _remember,
                          onChanged: (v) => setState(() => _remember = v),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Remember these matches — later imports using the '
                            'same names link without asking.',
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 12.5,
                              color: t.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          _StepFooter(
            note: '$linked linked · '
                '${_matches.length - linked - unmatched} kept separate · '
                '$unmatched saved recipe-only and flagged',
            primaryLabel: 'Save to library',
            onPrimary: () => _commit(context, app),
          ),
        ],
      ),
    );
  }

  Widget _matchRow(
    BuildContext context,
    AppState app,
    _Match match,
    bool divided,
  ) {
    final t = context.tokens;
    final item = match.pantryItemId == null
        ? null
        : app.pantryItem(match.pantryItemId!);

    return Container(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: t.divider)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.line.name,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 13,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  match.line.quantity == null
                      ? match.line.unit
                      : '${formatAmount(match.line.quantity)} ${match.line.unit}'
                          .trim(),
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward, size: 14, color: t.textFaint),
          const SizedBox(width: 14),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Tag(
                  switch (match.kind) {
                    _MatchKind.linked => item?.name ?? 'linked',
                    _MatchKind.branded => 'its own ingredient',
                    _MatchKind.unmatched => 'recipe-only · flagged',
                  },
                  style: switch (match.kind) {
                    _MatchKind.linked => TagStyle.accent,
                    _MatchKind.branded => TagStyle.neutral,
                    _MatchKind.unmatched => TagStyle.outline,
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    switch (match.kind) {
                      _MatchKind.linked => 'inherits its macros',
                      _MatchKind.branded => 'keeps its own macros',
                      _MatchKind.unmatched => 'no macros — never counted as 0',
                    },
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11,
                      color: t.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _MatchMenu(
            match: match,
            onChanged: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  void _commit(BuildContext context, AppState app) {
    final p = widget.parsed;

    final recipe = Recipe(
      id: newId(),
      title: p.title,
      mealTypeId: widget.mealTypeId,
      servings: p.servings ?? 4,
      sourceUrl: p.sourceUrl,
      totalMinutes: p.totalMinutes,
    );

    // An imported recipe arrives as one component; the desktop splits it into
    // named ones afterwards.
    final component = RecipeComponent(
      id: newId(),
      recipeId: recipe.id,
      name: 'Ingredients',
      order: 0,
    );
    recipe.components.add(component);

    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      recipe.ingredients.add(Ingredient(
        id: newId(),
        componentId: component.id,
        quantity: match.line.quantity,
        unit: match.line.unit,
        name: match.line.name,
        pantryItemId:
            match.kind == _MatchKind.linked ? match.pantryItemId : null,
        isBranded: match.kind == _MatchKind.branded,
        order: i,
      ));

      // Remembering a match means teaching the pantry item another name.
      if (_remember &&
          match.kind == _MatchKind.linked &&
          match.pantryItemId != null) {
        app.addAlias(match.pantryItemId!, match.line.name);
      }
    }

    for (var i = 0; i < p.steps.length; i++) {
      recipe.steps.add(RecipeStep(
        id: newId(),
        componentId: component.id,
        text: p.steps[i],
        order: i,
      ));
    }

    // Only this step commits.
    app.saveRecipe(recipe);

    Navigator.of(context)
      ..pop()
      ..pop();
    context.read<NavController>().openRecipe(recipe.id);
  }
}

class _MatchMenu extends StatelessWidget {
  const _MatchMenu({required this.match, required this.onChanged});

  final _Match match;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();

    return PopupMenuButton<String>(
      color: t.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: t.brContainer),
      icon: Icon(Icons.more_horiz, size: 17, color: t.textMuted),
      onSelected: (value) {
        if (value == '__branded__') {
          match
            ..kind = _MatchKind.branded
            ..pantryItemId = null;
        } else if (value == '__none__') {
          match
            ..kind = _MatchKind.unmatched
            ..pantryItemId = null;
        } else {
          match
            ..kind = _MatchKind.linked
            ..pantryItemId = value;
        }
        onChanged();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: '__branded__',
          height: 34,
          child: Text(
            'Keep as its own ingredient',
            style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12.5),
          ),
        ),
        PopupMenuItem(
          value: '__none__',
          height: 34,
          child: Text(
            'Save recipe-only',
            style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12.5),
          ),
        ),
        const PopupMenuDivider(),
        for (final item in app.pantry.items.take(40))
          PopupMenuItem(
            value: item.id,
            height: 32,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 13,
                  color: match.pantryItemId == item.id
                      ? t.accent
                      : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(
                  item.name,
                  style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12.5),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared chrome
// ═══════════════════════════════════════════════════════════════════════════

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.onDiscard,
  });

  final int step;
  final String title;
  final String subtitle;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 22, 30, 18),
      decoration: BoxDecoration(
        color: t.chrome,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (var i = 1; i <= 3; i++) ...[
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < step ? t.accent : Colors.transparent,
                        border: Border.fromBorderSide(
                          BorderSide(
                            color: i <= step ? t.accent : t.divider,
                          ),
                        ),
                      ),
                      child: i < step
                          ? Icon(Icons.check, size: 12, color: t.ground)
                          : Text(
                              '$i',
                              style: TextStyle(
                                fontFamily: t.bodyFamily,
                                fontSize: 11,
                                height: 1,
                                color: i == step ? t.accent : t.textFaint,
                              ),
                            ),
                    ),
                    if (i < 3)
                      Container(width: 26, height: 1, color: t.divider),
                  ],
                  const SizedBox(width: 14),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Discard at any point leaves the library untouched.
          AppButton('Discard', onPressed: onDiscard),
        ],
      ),
    );
  }
}

class _StepFooter extends StatelessWidget {
  const _StepFooter({
    required this.note,
    required this.primaryLabel,
    required this.onPrimary,
    this.highlight = false,
  });

  final String note;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 14, 30, 16),
      decoration: BoxDecoration(
        color: t.chrome,
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          Icon(
            highlight ? Icons.error_outline : Icons.info_outline,
            size: 15,
            color: highlight ? t.accent : t.textFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: highlight ? t.text : t.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 16),
          AppButton(
            primaryLabel,
            kind: ButtonKind.primary,
            onPressed: onPrimary,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.multiline = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final bool multiline;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 5, left: 2),
            child: Text(
              widget.label!,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11,
                color: t.textMuted,
              ),
            ),
          ),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          maxLines: widget.multiline ? null : 1,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 13,
            height: widget.multiline ? 1.5 : 1.25,
            color: t.text,
          ),
          cursorColor: t.accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            hintStyle: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 13,
              color: t.textFaint,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.transparent),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.transparent),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: t.accent),
            ),
          ),
        ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: value ? t.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(
              t.radiusControl > 100 ? 999 : 4,
            ),
            border: Border.fromBorderSide(
              BorderSide(color: value ? t.accent : t.divider, width: 1.5),
            ),
          ),
          child: value ? Icon(Icons.check, size: 11, color: t.ground) : null,
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
