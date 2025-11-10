// lib/data/local/utils/nutrition_calc.dart
import 'dart:math';
import '../../../domain/models.dart';

/// Alvo diário de energia e macronutrientes + métricas auxiliares.
///
/// Contém também indicadores calculados (IMC, BMR, TDEE) e idade resultante.
class DailyTargets {
  /// Calorias alvo (kcal).
  final int calories;

  /// Proteína alvo (g).
  final double proteinG;

  /// Hidratos de carbono alvo (g).
  final double carbG;

  /// Gordura alvo (g).
  final double fatG;

  /// Índice de Massa Corporal.
  final double bmi;

  /// BMR — Taxa Metabólica Basal (Mifflin-St Jeor).
  final double bmr;

  /// TDEE — Gasto energético diário total.
  final double tdee;

  /// Idade (anos) calculada a partir da data de nascimento.
  final int age;

  /// Cria um conjunto de alvos e métricas diárias.
  const DailyTargets({
    required this.calories,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.bmi,
    required this.bmr,
    required this.tdee,
    required this.age,
  });
}

/// Utilitários de cálculo nutricional do NutriScore.
///
/// Implementa:
/// - IMC (kg/cm);
/// - Idade a partir da data de nascimento;
/// - BMR (Mifflin–St Jeor);
/// - Fatores de atividade → TDEE;
/// - Delta calórico diário para objetivo de peso em data alvo;
/// - Resolução/normalização de percentagens de macros;
/// - Conversão percentagens → gramas;
/// - Cálculo completo de **DailyTargets** a partir de [UserGoalsModel].
class NutritionCalc {
  // ---- IMC

  /// Calcula o **IMC** dado o peso em kg e altura em cm.
  ///
  /// Usa salvaguarda para evitar divisão por zero.
  static double bmiKgCm({required double kg, required int heightCm}) {
    final h = max(0.001, heightCm / 100.0);
    return kg / (h * h);
  }

  // ---- Idade (anos) a partir de dateOfBirth (apenas data)

  /// Calcula a **idade** (anos) a partir de [dob].
  ///
  /// Se [dob] for `null`, devolve `30` como fallback neutro.
  /// O cálculo respeita se já fez anos no ano corrente.
  static int ageFromDob(DateTime? dob, {DateTime? today}) {
    if (dob == null) return 30; // fallback neutro
    final now = today ?? DateTime.now();
    int age = now.year - dob.year;
    final hadBirthday =
        (now.month > dob.month) || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age -= 1;
    return age.clamp(0, 120);
  }

  // ---- BMR (Mifflin - St Jeor)

  /// Calcula o **BMR** pela equação de **Mifflin–St Jeor**.
  ///
  /// [sex] deve ser `'MALE'`, `'FEMALE'` ou `'OTHER'` (média dos dois).
  static double bmrMifflin({
    required String sex, // 'MALE' | 'FEMALE' | 'OTHER'
    required double kg,
    required int heightCm,
    required int ageYears,
  }) {
    // 10*kg + 6.25*cm - 5*idade + s (s=+5 masculino, s=-161 feminino; OTHER = média)
    final base = 10 * kg + 6.25 * heightCm - 5 * ageYears;
    switch (sex) {
      case 'MALE':
        return base + 5;
      case 'FEMALE':
        return base - 161;
      default:
        return base + ((5 + (-161)) / 2); // média dos sexos para 'OTHER'
    }
  }

  // ---- Fator de atividade → TDEE

  /// Devolve o **fator de atividade** para o nível indicado.
  ///
  /// Valores padrão: `sedentary`, `light`, `moderate`, `active`, `very_active`.
  static double activityFactor(String level) {
    switch (level) {
      case 'sedentary':
        return 1.2;
      case 'light':
        return 1.375;
      case 'moderate':
        return 1.55;
      case 'active':
        return 1.725;
      case 'very_active':
        return 1.9;
      default:
        return 1.2;
    }
  }

  /// Calcula o **TDEE** a partir de [bmr] e [activityLevel].
  static double tdeeFromBmr(double bmr, String activityLevel) {
    return bmr * activityFactor(activityLevel);
  }

  // ---- Ajuste calórico em função de peso-alvo e data-alvo (se houver)
  // regra prática: 1 kg ~ 7700 kcal

  /// Calcula o **delta calórico diário** necessário para atingir [targetKg] em [targetDate].
  ///
  /// Regra empírica: `1 kg ≈ 7700 kcal`. Limita a ±1000 kcal/dia por segurança.
  /// Se [targetKg] ou [targetDate] forem `null`, devolve `0`.
  static int dailyDeltaFromGoal({
    required double currentKg,
    double? targetKg,
    DateTime? targetDate,
    DateTime? today,
  }) {
    if (targetKg == null || targetDate == null) return 0;
    final now = today ?? DateTime.now();
    int days = targetDate.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 1) days = 1;

    final diffKg = targetKg - currentKg; // negativo = perder peso
    final totalKcal = diffKg * 7700.0;
    final perDay = totalKcal / days;

    // Segurança: não passar de ±1000 kcal/dia
    return perDay.round().clamp(-1000, 1000);
  }

  // ---- Macros em percentagem (defaults 50/20/30)

  /// Normaliza as percentagens de macros, garantindo soma de **100%**.
  ///
  /// Defaults: carb `50`, protein `20`, fat `30`. Se a soma diferir,
  /// reescala mantendo a razão aproximada.
  static ({int carb, int protein, int fat}) resolveMacroPercents({
    int? carbPercent,
    int? proteinPercent,
    int? fatPercent,
  }) {
    final c = carbPercent ?? 50;
    final p = proteinPercent ?? 20;
    final f = fatPercent ?? 30;
    final total = c + p + f;
    if (total == 100) return (carb: c, protein: p, fat: f);

    // normalizar mantendo a razão aproximada
    final cc = (c / total * 100).round();
    final pp = (p / total * 100).round();
    int ff = 100 - cc - pp;
    if (ff < 0) ff = 0;
    return (carb: cc, protein: pp, fat: ff);
  }

  // ---- Convert percent → gramas (4/4/9 kcal/g)

  /// Converte percentagens de macros em **gramas**, dado [kcal] total.
  ///
  /// Conversões: 4 kcal/g (hidratos, proteína), 9 kcal/g (gordura).
  static ({double carbG, double proteinG, double fatG}) gramsFromPercents({
    required int kcal,
    required int carbPercent,
    required int proteinPercent,
    required int fatPercent,
  }) {
    final carbKcal = (kcal * carbPercent / 100.0);
    final protKcal = (kcal * proteinPercent / 100.0);
    final fatKcal = (kcal * fatPercent / 100.0);

    return (
      carbG: carbKcal / 4.0,
      proteinG: protKcal / 4.0,
      fatG: fatKcal / 9.0,
    );
  }

  // ---- Plano diário completo a partir de UserGoalsModel

  /// Calcula o plano diário completo ([DailyTargets]) a partir de [UserGoalsModel].
  ///
  /// Etapas:
  /// 1) Idade e IMC;
  /// 2) BMR (Mifflin-St Jeor);
  /// 3) TDEE (BMR × fator de atividade);
  /// 4) Ajuste calórico diário ([dailyDeltaFromGoal]);
  /// 5) Percentagens de macros ([resolveMacroPercents]) → gramas ([gramsFromPercents]).
  ///
  /// Aplica um **piso mínimo** de `1000 kcal`.
  static DailyTargets computeFromGoals(UserGoalsModel g, {DateTime? today}) {
    final age = ageFromDob(g.dateOfBirth, today: today);
    final bmi = bmiKgCm(kg: g.currentWeightKg, heightCm: g.heightCm);
    final bmr = bmrMifflin(
      sex: g.sex,
      kg: g.currentWeightKg,
      heightCm: g.heightCm,
      ageYears: age,
    );
    final tdee = tdeeFromBmr(bmr, g.activityLevel);

    final delta = dailyDeltaFromGoal(
      currentKg: g.currentWeightKg,
      targetKg: g.targetWeightKg == 0 ? null : g.targetWeightKg,
      targetDate: g.targetDate,
      today: today,
    );

    final targetKcal = max(1000, (tdee + delta).round()); // piso simples
    final p = resolveMacroPercents(
      carbPercent: g.carbPercent,
      proteinPercent: g.proteinPercent,
      fatPercent: g.fatPercent,
    );
    final grams = gramsFromPercents(
      kcal: targetKcal,
      carbPercent: p.carb,
      proteinPercent: p.protein,
      fatPercent: p.fat,
    );

    return DailyTargets(
      calories: targetKcal,
      proteinG: grams.proteinG,
      carbG: grams.carbG,
      fatG: grams.fatG,
      bmi: bmi,
      bmr: bmr,
      tdee: tdee,
      age: age,
    );
  }
}
