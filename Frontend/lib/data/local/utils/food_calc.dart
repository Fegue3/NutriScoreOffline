// lib/data/local/utils/food_calc.dart
class Nutr100g {
  final int? kcal;
  final double? protein, carb, fat, sugars, fiber, salt;
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

class CalcResult {
  final double gramsTotal;
  final int kcal;
  final double protein, carb, fat, sugars, fiber, salt;
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

/// Converte quantidade → nutrientes, partindo de valores por 100g.
/// - unit: 'GRAM' | 'ML' | 'PIECE'
/// - gramsPerUnit: densidade (ml→g) ou peso por peça (se aplicável)
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
