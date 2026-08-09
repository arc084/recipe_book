import 'package:flutter/material.dart';

/// The five places the sidebar goes.
///
/// The recipe screen, cook mode and the import flow are not tabs — a recipe
/// opens inside the Library's column, and cook mode is the one full-window
/// mode in the app.
enum AppTab {
  library('Library', Icons.menu_book_outlined),
  pantry('Pantry', Icons.kitchen_outlined),
  groceries('Groceries', Icons.shopping_cart_outlined),
  plan('Meal Plan', Icons.calendar_month_outlined),
  settings('Settings', Icons.settings_outlined);

  const AppTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class NavController extends ChangeNotifier {
  AppTab _tab = AppTab.library;
  String? _recipeId;
  bool _editing = false;
  String? _pantryItemId;

  AppTab get tab => _tab;

  /// Non-null when a recipe is open in the Library's column.
  String? get recipeId => _recipeId;
  bool get editing => _editing;

  /// Which pantry item the Pantry tab's detail column is showing.
  String? get pantryItemId => _pantryItemId;

  void go(AppTab tab) {
    if (_tab == tab && _recipeId == null) return;
    _tab = tab;
    _recipeId = null;
    _editing = false;
    notifyListeners();
  }

  void openRecipe(String id, {bool edit = false}) {
    _tab = AppTab.library;
    _recipeId = id;
    _editing = edit;
    notifyListeners();
  }

  void editRecipe(bool value) {
    _editing = value;
    notifyListeners();
  }

  void closeRecipe() {
    _recipeId = null;
    _editing = false;
    notifyListeners();
  }

  void openPantryItem(String? id) {
    _pantryItemId = id;
    notifyListeners();
  }
}
