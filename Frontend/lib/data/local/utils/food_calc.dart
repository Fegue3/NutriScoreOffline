// lib/data/local/utils/food_calc.dart

/// NutriScore — Cálculo de Nutrientes a partir de Quantidades
///
/// Utilitários para converter **quantidades ingeridas** (g/ml/peça)
/// em **nutrientes absolutos**, partindo de valores **por 100 g**.
library;


/// Valores nutricionais **por 100 g**.
///
/// Campos opcionais: quando `null`, são tratados como `0` nos cálculos.
class Nutr100g {
  /// Quilocalorias por 100 g.
  final int? kcal;

  /// Proteína (g) por 100 g.
  final double? protein;

  /// Hidratos de carbono (g) por 100 g.
  final double? carb;

  /// Gordura (g) por 100 g.
  final double? fat;

  /// Açúcares (g) por 100 g.
  final double? sugars;

  /// Fibra (g) por 100 g.
  final double? fiber;

  /// Sal (g) por 100 g.
  final double? salt;

  /// Cria um contentor de valores por 100 g.
  const Nutr100g({
    this.kcal,
    this.protein,
    this.carb,
    this.fat,
    this.sugars,
    this.fiber,
    this.salt,
  });
}

/// Resultado do cálculo de nutrientes para uma **quantidade específica**.
class CalcResult {
  /// Quantidade total convertida para **gramas**.
  final double gramsTotal;

  /// Quilocalorias totais resultantes.
  final int kcal;

  /// Proteína total (g).
  final double protein;

  /// Hidratos totais (g).
  final double carb;

  /// Gordura total (g).
  final double fat;

  /// Açúcares totais (g).
  final double sugars;

  /// Fibra total (g).
  final double fiber;

  /// Sal total (g).
  final double salt;

  /// Cria um resultado com os nutrientes calculados.
  const CalcResult({
    required this.gramsTotal,
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.sugars,
    required this.fiber,
    required this.salt,
  });
}

/// Converte **quantidade → nutrientes** partindo de valores **por 100 g**.
///
/// - [unit]:
///   - `'GRAM'`  → [quantity] já está em **gramas**;
///   - `'ML'`    → [quantity] em **mililitros**; usa [gramsPerUnit] como densidade
///                 (g por ml). Se omitido, assume `1.0 g/ml`;
///   - `'PIECE'` → [quantity] em **número de peças**; usa [gramsPerUnit] como
///                 **peso por peça**. Se omitido, assume que [quantity] já é em g.
/// - [n]: valores por 100 g.
/// - Retorna um [CalcResult] com totais absolutos.
///
/// Exemplos:
/// ```dart
/// // 250 g de um alimento com 120 kcal/100g → 300 kcal
/// calcPerQuantity(unit: 'GRAM', quantity: 250, n: Nutr100g(kcal: 120));
///
/// // 200 ml, densidade 1.03 g/ml → 206 g equivalentes
/// calcPerQuantity(unit: 'ML', quantity: 200, gramsPerUnit: 1.03, n: Nutr100g(kcal: 60));
///
/// // 2 peças, 35 g cada → 70 g equivalentes
/// calcPerQuantity(unit: 'PIECE', quantity: 2, gramsPerUnit: 35, n: Nutr100g(protein: 5.2));
/// ```
CalcResult calcPerQuantity({
  required String unit,
  required double quantity,
  required Nutr100g n,
  double? gramsPerUnit,
}) {
  double grams;
  switch (unit) {
    case 'GRAM':
      grams = quantity;
      break;
    case 'ML':
      grams = quantity * (gramsPerUnit ?? 1.0);
      break;
    case 'PIECE':
      grams = (gramsPerUnit ?? quantity) * 1.0;
      break;
    default:
      grams = quantity;
  }
  final factor = grams / 100.0;
  final kcal = ((n.kcal ?? 0) * factor).round();
  double v(double? x) => (x ?? 0.0) * factor;

  return CalcResult(
    gramsTotal: grams,
    kcal: kcal,
    protein: v(n.protein),
    carb: v(n.carb),
    fat: v(n.fat),
    sugars: v(n.sugars),
    fiber: v(n.fiber),
    salt: v(n.salt),
  );
}
