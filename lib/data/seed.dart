import 'database.dart';
import 'models.dart';

/// What a fresh install starts with.
///
/// The content mirrors the prototype's screens. The macro *figures* on those
/// screens are not copied across — the app calculates its own from the pantry
/// values below, which is the rule everywhere else in the app. What is seeded
/// here are label values a packet would actually carry.
abstract final class Seed {
  static ({LibraryDatabase library, PantryDatabase pantry}) build() {
    // ── Meal types ────────────────────────────────────────────────────────
    final breakfast = MealType(
      id: seedId('mealType', 'Breakfast'),
      name: 'Breakfast',
      order: 0,
    );
    final lunch = MealType(
      id: seedId('mealType', 'Lunch'),
      name: 'Lunch',
      order: 1,
    );
    final dinner = MealType(
      id: seedId('mealType', 'Dinner'),
      name: 'Dinner',
      order: 2,
    );
    final snacks = MealType(
      id: seedId('mealType', 'Snacks'),
      name: 'Snacks',
      order: 3,
    );
    final sides = MealType(
      id: seedId('mealType', 'Sides'),
      name: 'Sides',
      order: 4,
    );
    final dessert = MealType(
      id: seedId('mealType', 'Dessert'),
      name: 'Dessert',
      order: 5,
    );
    final mealTypes = [breakfast, lunch, dinner, snacks, sides, dessert];

    // ── Pantry ────────────────────────────────────────────────────────────
    PantryItem p(
      String name, {
      PantryGroup group = PantryGroup.pantry,
      List<String> aliases = const [],
      bool staple = false,
      String? brand,
      double? serving,
      String servingUnit = 'g',
      double? alt,
      String? altUnit,
      double? pack,
      String? packUnit,
      MacroBasis basis = MacroBasis.per100g,
      double? cal,
      double? protein,
      double? fat,
      double? carbs,
      double? sugar,
      bool estimated = false,
    }) => PantryItem(
      id: seedId('pantryItem', name),
      name: name,
      group: group,
      aliases: [...aliases],
      isStaple: staple,
      brandLabel: brand,
      servingAmount: serving,
      servingUnit: servingUnit,
      altAmount: alt,
      altUnit: altUnit,
      packAmount: pack,
      packUnit: packUnit,
      basis: basis,
      calories: cal,
      protein: protein,
      fat: fat,
      carbs: carbs,
      sugar: sugar,
      isEstimated: estimated,
      enteredOn: cal == null ? null : DateTime(2026, 3, 12),
    );

    // Fridge
    final chicken = p(
      'chicken breast',
      group: PantryGroup.fridge,
      aliases: ['chicken cutlets', 'chicken breasts', 'chicken'],
      serving: 150,
      alt: 1,
      altUnit: 'cutlet',
      cal: 165,
      protein: 31,
      fat: 3.6,
      carbs: 0,
      sugar: 0,
    );
    final eggs = p(
      'eggs',
      group: PantryGroup.fridge,
      aliases: ['egg', 'eggs, beaten', 'beaten eggs'],
      basis: MacroBasis.perServing,
      serving: 1,
      servingUnit: 'egg',
      cal: 72,
      protein: 6.3,
      fat: 4.8,
      carbs: 0.4,
      sugar: 0.2,
    );
    final mozzarella = p(
      'mozzarella',
      group: PantryGroup.fridge,
      aliases: ['fresh mozzarella', 'mozzarella ball'],
      serving: 125,
      alt: 1,
      altUnit: 'ball',
      cal: 280,
      protein: 18,
      fat: 22,
      carbs: 2.2,
      sugar: 1,
    );
    final parmesan = p(
      'parmesan',
      group: PantryGroup.fridge,
      aliases: ['parmesan, grated', 'grated parmesan', 'parmigiano'],
      serving: 30,
      alt: 4,
      altUnit: 'tbsp',
      cal: 431,
      protein: 38,
      fat: 29,
      carbs: 4.1,
      sugar: 0.9,
    );
    // No macros yet — this is one of the two the footer counts.
    final basil = p(
      'basil',
      group: PantryGroup.fridge,
      aliases: ['fresh basil'],
    );
    final butter = p(
      'butter',
      group: PantryGroup.fridge,
      serving: 14,
      alt: 1,
      altUnit: 'tbsp',
      cal: 717,
      protein: 0.9,
      fat: 81,
      carbs: 0.1,
      sugar: 0.1,
    );

    // Pantry
    final chocChips = p(
      'chocolate chips',
      aliases: ['choc chips', 'semi-sweet chips', 'dark chocolate chips'],
      brand: "Trader Joe's No Sugar Added Dark Chocolate Chips",
      serving: 30,
      alt: 2,
      altUnit: 'tbsp',
      pack: 283,
      packUnit: 'g',
      cal: 521,
      protein: 8,
      fat: 38,
      carbs: 46,
      sugar: 2,
    );
    final tomatoes = p(
      'canned tomatoes',
      aliases: ['chopped tomatoes', 'tinned tomatoes', 'plum tomatoes'],
      pack: 400,
      packUnit: 'g',
      cal: 32,
      protein: 1.6,
      fat: 0.3,
      carbs: 5.2,
      sugar: 4.5,
    );
    final oliveOil = p(
      'olive oil',
      aliases: ['oil', 'extra virgin olive oil'],
      staple: true,
      serving: 13.5,
      alt: 1,
      altUnit: 'tbsp',
      cal: 884,
      protein: 0,
      fat: 100,
      carbs: 0,
      sugar: 0,
    );
    final cocoa = p(
      'cocoa powder',
      aliases: ['cacao powder'],
      cal: 228,
      protein: 19.6,
      fat: 13.7,
      carbs: 57.9,
      sugar: 1.8,
    );
    // No macros yet — the second of the two.
    final onions = p(
      'onions',
      aliases: ['onion', 'onion, diced', 'brown onion'],
    );
    final chickpeas = p(
      'chickpeas',
      aliases: ['garbanzo beans', 'canned chickpeas'],
      pack: 400,
      packUnit: 'g',
      cal: 164,
      protein: 8.9,
      fat: 2.6,
      carbs: 27.4,
      sugar: 4.8,
    );

    // Freezer
    final salmon = p(
      'salmon fillets',
      group: PantryGroup.freezer,
      aliases: ['salmon', 'salmon fillet'],
      serving: 150,
      alt: 1,
      altUnit: 'fillet',
      cal: 208,
      protein: 20,
      fat: 13,
      carbs: 0,
      sugar: 0,
    );
    final peas = p(
      'peas',
      group: PantryGroup.freezer,
      aliases: ['frozen peas'],
      cal: 81,
      protein: 5.4,
      fat: 0.4,
      carbs: 14.5,
      sugar: 5.7,
    );
    final pastry = p(
      'puff pastry',
      group: PantryGroup.freezer,
      cal: 551,
      protein: 7,
      fat: 38,
      carbs: 45,
      sugar: 1.5,
    );

    // Staples — assumed on hand and excluded from missing counts.
    final salt = p(
      'salt',
      staple: true,
      cal: 0,
      protein: 0,
      fat: 0,
      carbs: 0,
      sugar: 0,
    );
    final pepper = p(
      'pepper',
      staple: true,
      aliases: ['black pepper'],
      cal: 251,
      protein: 10.4,
      fat: 3.3,
      carbs: 64,
      sugar: 0.6,
    );
    final sugarItem = p(
      'sugar',
      staple: true,
      cal: 387,
      protein: 0,
      fat: 0,
      carbs: 100,
      sugar: 100,
    );
    final flour = p(
      'flour',
      staple: true,
      aliases: ['plain flour', 'all-purpose flour'],
      cal: 364,
      protein: 10,
      fat: 1,
      carbs: 76,
      sugar: 0.3,
    );

    // Things other seeded recipes draw on.
    final oats = p(
      'rolled oats',
      aliases: ['oats', 'porridge oats'],
      cal: 379,
      protein: 13.2,
      fat: 6.5,
      carbs: 67.7,
      sugar: 0.99,
    );
    final yogurt = p(
      'greek yogurt',
      group: PantryGroup.fridge,
      aliases: ['yoghurt', 'greek yoghurt'],
      cal: 59,
      protein: 10,
      fat: 0.4,
      carbs: 3.6,
      sugar: 3.2,
    );
    final milk = p(
      'milk',
      group: PantryGroup.fridge,
      serving: 240,
      alt: 1,
      altUnit: 'cup',
      cal: 42,
      protein: 3.4,
      fat: 1,
      carbs: 5,
      sugar: 5,
    );
    final tuna = p(
      'sushi-grade tuna',
      group: PantryGroup.freezer,
      aliases: ['tuna', 'ahi tuna'],
      cal: 144,
      protein: 23.3,
      fat: 4.9,
      carbs: 0,
      sugar: 0,
    );
    final rice = p(
      'sushi rice',
      aliases: ['rice', 'short-grain rice'],
      cal: 358,
      protein: 6.5,
      fat: 0.6,
      carbs: 79,
      sugar: 0.1,
    );
    final soy = p(
      'soy sauce',
      aliases: ['shoyu'],
      serving: 18,
      alt: 1,
      altUnit: 'tbsp',
      cal: 53,
      protein: 8.1,
      fat: 0.6,
      carbs: 4.9,
      sugar: 0.4,
    );
    final curryRoux = p(
      'curry roux',
      aliases: ['japanese curry roux', 'curry blocks'],
      pack: 220,
      packUnit: 'g',
      cal: 474,
      protein: 5.9,
      fat: 30,
      carbs: 45,
      sugar: 12,
      estimated: true,
    );
    final potato = p(
      'potatoes',
      aliases: ['potato'],
      serving: 170,
      alt: 1,
      altUnit: 'potato',
      cal: 77,
      protein: 2,
      fat: 0.1,
      carbs: 17,
      sugar: 0.8,
    );
    final carrot = p(
      'carrots',
      group: PantryGroup.fridge,
      aliases: ['carrot'],
      serving: 61,
      alt: 1,
      altUnit: 'carrot',
      cal: 41,
      protein: 0.9,
      fat: 0.2,
      carbs: 10,
      sugar: 4.7,
    );
    final coconutMilk = p(
      'coconut milk',
      pack: 400,
      packUnit: 'ml',
      cal: 197,
      protein: 2,
      fat: 21,
      carbs: 3,
      sugar: 3,
    );
    final spinach = p(
      'spinach',
      group: PantryGroup.fridge,
      cal: 23,
      protein: 2.9,
      fat: 0.4,
      carbs: 3.6,
      sugar: 0.4,
    );
    final chiaSeeds = p(
      'chia seeds',
      cal: 486,
      protein: 16.5,
      fat: 30.7,
      carbs: 42.1,
      sugar: 0,
    );
    final maple = p(
      'maple syrup',
      serving: 20,
      alt: 1,
      altUnit: 'tbsp',
      cal: 260,
      protein: 0,
      fat: 0.1,
      carbs: 67,
      sugar: 60,
    );
    final avocado = p(
      'avocado',
      group: PantryGroup.fridge,
      serving: 150,
      alt: 1,
      altUnit: 'avocado',
      cal: 160,
      protein: 2,
      fat: 15,
      carbs: 9,
      sugar: 0.7,
    );
    final cucumber = p(
      'cucumber',
      group: PantryGroup.fridge,
      cal: 15,
      protein: 0.7,
      fat: 0.1,
      carbs: 3.6,
      sugar: 1.7,
    );
    final sesameOil = p(
      'sesame oil',
      serving: 13.6,
      alt: 1,
      altUnit: 'tbsp',
      cal: 884,
      protein: 0,
      fat: 100,
      carbs: 0,
      sugar: 0,
    );
    final paprika = p(
      'smoked paprika',
      staple: false,
      serving: 2.3,
      alt: 1,
      altUnit: 'tsp',
      cal: 282,
      protein: 14.1,
      fat: 13,
      carbs: 54,
      sugar: 10.3,
    );
    final cumin = p(
      'cumin',
      serving: 2.1,
      alt: 1,
      altUnit: 'tsp',
      cal: 375,
      protein: 17.8,
      fat: 22.3,
      carbs: 44.2,
      sugar: 2.3,
    );

    final pantryItems = <PantryItem>[
      chicken,
      eggs,
      mozzarella,
      parmesan,
      basil,
      butter,
      chocChips,
      tomatoes,
      oliveOil,
      cocoa,
      onions,
      chickpeas,
      salmon,
      peas,
      pastry,
      salt,
      pepper,
      sugarItem,
      flour,
      oats,
      yogurt,
      milk,
      tuna,
      rice,
      soy,
      curryRoux,
      potato,
      carrot,
      coconutMilk,
      spinach,
      chiaSeeds,
      maple,
      avocado,
      cucumber,
      sesameOil,
      paprika,
      cumin,
    ];

    // ── Recipes ───────────────────────────────────────────────────────────
    // A small builder so a recipe reads close to how it is written down.
    Recipe recipe({
      required String title,
      required MealType type,
      required List<String> tags,
      int servings = 4,
      String? source,
      int? minutes,
      int cooked = 0,
      String notes = '',
      required List<
        (String, List<(double?, String, String, PantryItem?)>, List<String>)
      >
      parts,
    }) {
      final r = Recipe(
        id: seedId('recipe', title),
        title: title,
        mealTypeId: type.id,
        tags: tags,
        servings: servings,
        sourceUrl: source,
        totalMinutes: minutes,
        timesCooked: cooked,
        notes: notes,
      );
      var componentOrder = 0;
      var ingredientOrder = 0;
      var stepOrder = 0;
      for (final (name, lines, steps) in parts) {
        final c = RecipeComponent(
          id: seedId('component', '$title|$name'),
          recipeId: r.id,
          name: name,
          order: componentOrder++,
        );
        r.components.add(c);
        for (final (qty, unit, ingName, link) in lines) {
          r.ingredients.add(
            Ingredient(
              id: seedId(
                'ingredient',
                '$title|$name|$ingName|$ingredientOrder',
              ),
              componentId: c.id,
              quantity: qty,
              unit: unit,
              name: ingName,
              pantryItemId: link?.id,
              order: ingredientOrder++,
            ),
          );
        }
        for (final text in steps) {
          r.steps.add(
            RecipeStep(
              id: seedId('step', '$title|$name|$stepOrder'),
              componentId: c.id,
              text: text,
              order: stepOrder++,
            ),
          );
        }
      }
      return r;
    }

    final chickenParm = recipe(
      title: 'Chicken Parmesan',
      type: dinner,
      tags: ['high-protein', 'comfort'],
      servings: 4,
      source: 'https://www.seriouseats.com',
      minutes: 40,
      cooked: 4,
      notes:
          'Sauce is better made the day before. Half quantities fit one '
          'pan; doubling means frying in batches or the crust steams.',
      parts: [
        (
          'Cutlets',
          [(4, '', 'Chicken cutlets', chicken)],
          [
            'Butterfly the cutlets and pound them to an even 1 cm. Season '
                'both sides and leave them out while you set up the breading.',
          ],
        ),
        (
          'Breading',
          [
            (2, '', 'Eggs, beaten', eggs),
            // Not in the pantry — this is the one missing item.
            (100, 'g', 'Panko breadcrumbs', null),
            (60, 'g', 'Parmesan, grated', parmesan),
          ],
          [
            'Set out three dishes: flour, beaten eggs, and panko mixed with '
                'half the parmesan.',
            'Bread the cutlets: flour, egg, then the panko and parmesan mix. '
                'Press the crumbs on firmly.',
          ],
        ),
        (
          'Tomato sauce',
          [
            (400, 'g', 'Canned tomatoes', tomatoes),
            (1, '', 'Onion, diced', onions),
            (2, 'tbsp', 'Olive oil', oliveOil),
          ],
          [
            'Simmer the tomatoes with the onion and a glug of oil for 20 '
                'minutes, until it thickens. Season and set aside.',
          ],
        ),
        (
          'Fry & finish',
          [
            (2, 'balls', 'Fresh mozzarella', mozzarella),
            (null, 'handful', 'Basil', basil),
          ],
          [
            'Fry in a shallow pan over medium-high heat, three minutes a '
                'side, until deep golden. Drain on a rack, not paper.',
            'Spoon sauce over each cutlet, top with torn mozzarella and the '
                'rest of the parmesan, and grill until blistered. Finish with '
                'basil.',
          ],
        ),
      ],
    );

    final overnightOats = recipe(
      title: 'Overnight Oats',
      type: breakfast,
      tags: ['no-cook', 'meal-prep'],
      servings: 1,
      minutes: 5,
      parts: [
        (
          'The jar',
          [
            (80, 'g', 'Rolled oats', oats),
            (150, 'g', 'Greek yogurt', yogurt),
            (120, 'ml', 'Milk', milk),
            (15, 'g', 'Chia seeds', chiaSeeds),
            (1, 'tbsp', 'Maple syrup', maple),
          ],
          [
            'Stir everything together in a jar, seal it, and leave it in the '
                'fridge overnight.',
            'Loosen with a splash more milk in the morning.',
          ],
        ),
      ],
    );

    final curry = recipe(
      title: 'Japanese Chicken Curry',
      type: dinner,
      tags: ['high-protein', 'comfort'],
      servings: 4,
      minutes: 35,
      parts: [
        (
          'The pot',
          [
            (500, 'g', 'Chicken breast', chicken),
            (2, '', 'Onions', onions),
            (2, '', 'Carrots', carrot),
            (3, '', 'Potatoes', potato),
            (1, 'tbsp', 'Olive oil', oliveOil),
          ],
          [
            'Brown the chicken in the oil, then lift it out.',
            'Soften the onion, carrot and potato in the same pot for ten '
                'minutes.',
          ],
        ),
        (
          'Finish',
          [(110, 'g', 'Curry roux', curryRoux), (600, 'ml', 'Water', null)],
          [
            'Return the chicken, add the water, and simmer until the '
                'vegetables give.',
            'Off the heat, melt the roux blocks in and simmer five more '
                'minutes until it coats a spoon.',
          ],
        ),
      ],
    );

    final salmonRecipe = recipe(
      title: 'Air Fryer Salmon',
      type: dinner,
      tags: ['air-fryer', 'omega-3'],
      servings: 2,
      minutes: 12,
      parts: [
        (
          'Salmon',
          [
            (2, 'fillets', 'Salmon fillets', salmon),
            (1, 'tbsp', 'Olive oil', oliveOil),
            (1, 'tsp', 'Smoked paprika', paprika),
          ],
          [
            'Pat the fillets dry, rub with oil and paprika, and season.',
            'Air fry at 200°C for nine minutes, skin down, until it flakes.',
          ],
        ),
      ],
    );

    final poke = recipe(
      title: 'Tuna Poke Bowl',
      type: lunch,
      tags: ['high-protein', 'fresh'],
      servings: 2,
      minutes: 20,
      parts: [
        (
          'Bowl',
          [
            (300, 'g', 'Sushi-grade tuna', tuna),
            (150, 'g', 'Sushi rice', rice),
            (1, '', 'Avocado', avocado),
            (100, 'g', 'Cucumber', cucumber),
          ],
          [
            'Cook the rice and let it cool to room temperature.',
            'Dice the tuna, avocado and cucumber into even cubes.',
          ],
        ),
        (
          'Dressing',
          [(2, 'tbsp', 'Soy sauce', soy), (1, 'tbsp', 'Sesame oil', sesameOil)],
          [
            'Whisk the dressing, fold it through the tuna, and build the '
                'bowls.',
          ],
        ),
      ],
    );

    final stew = recipe(
      title: 'Spicy Chickpea Stew',
      type: lunch,
      tags: ['vegetarian', 'quick'],
      servings: 4,
      minutes: 25,
      parts: [
        (
          'Stew',
          [
            (800, 'g', 'Chickpeas', chickpeas),
            (400, 'g', 'Canned tomatoes', tomatoes),
            (400, 'ml', 'Coconut milk', coconutMilk),
            (1, '', 'Onion', onions),
            (100, 'g', 'Spinach', spinach),
            (2, 'tsp', 'Cumin', cumin),
            (2, 'tbsp', 'Olive oil', oliveOil),
          ],
          [
            'Soften the onion in the oil, then toast the cumin for a minute.',
            'Add the chickpeas, tomatoes and coconut milk and simmer fifteen '
                'minutes.',
            'Wilt the spinach through at the end and season hard.',
          ],
        ),
      ],
    );

    final crispyChickpeas = recipe(
      title: 'Crispy Chickpeas',
      type: snacks,
      tags: ['air-fryer', 'crunchy'],
      servings: 4,
      minutes: 22,
      parts: [
        (
          'Chickpeas',
          [
            (400, 'g', 'Chickpeas', chickpeas),
            (1, 'tbsp', 'Olive oil', oliveOil),
            (1, 'tsp', 'Smoked paprika', paprika),
          ],
          [
            'Drain and dry the chickpeas thoroughly — wet ones steam.',
            'Toss with oil and paprika, then air fry at 190°C for twenty '
                'minutes, shaking twice.',
          ],
        ),
      ],
    );

    final brownies = recipe(
      title: 'Fudgy Brownies',
      type: dessert,
      tags: ['quick'],
      servings: 12,
      minutes: 35,
      parts: [
        (
          'Batter',
          [
            (200, 'g', 'Chocolate chips', chocChips),
            (150, 'g', 'Butter', butter),
            (3, '', 'Eggs', eggs),
            (200, 'g', 'Sugar', sugarItem),
            (90, 'g', 'Flour', flour),
            (40, 'g', 'Cocoa powder', cocoa),
          ],
          [
            'Melt the butter with half the chocolate chips and let it cool a '
                'little.',
            'Whisk the eggs and sugar until pale, then fold in the chocolate.',
            'Fold in the flour and cocoa, stir through the rest of the chips, '
                'and bake at 180°C for 25 minutes.',
          ],
        ),
      ],
    );

    final recipes = [
      chickenParm,
      overnightOats,
      curry,
      salmonRecipe,
      poke,
      stew,
      crispyChickpeas,
      brownies,
    ];

    // ── Aisles and groceries ──────────────────────────────────────────────
    final produce = Aisle(
      id: seedId('aisle', 'Produce'),
      name: 'Produce',
      order: 0,
    );
    final bakery = Aisle(
      id: seedId('aisle', 'Bakery'),
      name: 'Bakery',
      order: 1,
    );
    final dairy = Aisle(id: seedId('aisle', 'Dairy'), name: 'Dairy', order: 2);
    final tinned = Aisle(
      id: seedId('aisle', 'Tinned & dry'),
      name: 'Tinned & dry',
      order: 3,
    );
    final aisles = [produce, bakery, dairy, tinned];

    final groceries = <GroceryItem>[
      GroceryItem(
        id: seedId('grocery', 'Panko breadcrumbs'),
        name: 'Panko breadcrumbs',
        aisleId: bakery.id,
        quantity: '100 g',
        sources: ['Chicken Parmesan'],
      ),
      GroceryItem(
        id: seedId('grocery', 'Lemons'),
        name: 'Lemons',
        aisleId: produce.id,
        quantity: '2',
        sources: ['Added by hand'],
      ),
      GroceryItem(
        id: seedId('grocery', 'Double cream'),
        name: 'Double cream',
        aisleId: dairy.id,
        quantity: '300 ml',
        sources: ['Chicken Marsala'],
      ),
      GroceryItem(
        id: seedId('grocery', 'Chestnut mushrooms'),
        name: 'Chestnut mushrooms',
        aisleId: produce.id,
        quantity: '250 g',
        sources: ['Chicken Marsala'],
      ),
      GroceryItem(
        id: seedId('grocery', 'Flat-leaf parsley'),
        name: 'Flat-leaf parsley',
        aisleId: produce.id,
        quantity: '1 bunch',
        sources: ['Added by hand'],
      ),
      GroceryItem(
        id: seedId('grocery', 'Coconut milk'),
        name: 'Coconut milk',
        aisleId: tinned.id,
        quantity: '400 ml',
        sources: ['Spicy Chickpea Stew'],
        pantryItemId: coconutMilk.id,
      ),
      GroceryItem(
        id: seedId('grocery', 'Nori sheets'),
        name: 'Nori sheets',
        aisleId: tinned.id,
        quantity: '1 pack',
        sources: ['Tuna Poke Bowl'],
      ),
      GroceryItem(
        id: seedId('grocery', 'Spring onions'),
        name: 'Spring onions',
        aisleId: produce.id,
        quantity: '1 bunch',
        sources: ['Tuna Poke Bowl'],
      ),
      GroceryItem(
        id: seedId('grocery', 'Olive oil'),
        name: 'Olive oil',
        aisleId: tinned.id,
        quantity: '500 ml',
        sources: ['Added by hand'],
        checked: true,
        pantryItemId: oliveOil.id,
      ),
    ];

    // ── This week's plan ──────────────────────────────────────────────────
    final today = DateTime.now();
    final monday = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - 1));
    PlanEntry entry(int dayOffset, MealSlot slot, Recipe r) => PlanEntry(
      id: seedId('planEntry', '$dayOffset|${slot.name}'),
      date: monday.add(Duration(days: dayOffset)),
      slot: slot,
      recipeId: r.id,
    );

    final plan = <PlanEntry>[
      entry(0, MealSlot.breakfast, overnightOats),
      entry(0, MealSlot.lunch, stew),
      entry(1, MealSlot.lunch, poke),
      entry(1, MealSlot.dinner, curry),
      entry(2, MealSlot.breakfast, overnightOats),
      entry(3, MealSlot.dinner, chickenParm),
      entry(3, MealSlot.snack, crispyChickpeas),
      entry(4, MealSlot.dinner, salmonRecipe),
      entry(5, MealSlot.lunch, poke),
      entry(6, MealSlot.dinner, curry),
    ];

    return (
      library: LibraryDatabase(
        recipes: recipes,
        mealTypes: mealTypes,
        aisles: aisles,
        groceries: groceries,
        plan: plan,
      ),
      pantry: PantryDatabase(items: pantryItems),
    );
  }
}
