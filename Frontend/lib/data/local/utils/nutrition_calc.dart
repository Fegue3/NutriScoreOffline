// lib/data/local/utils/nutrition_calc.dart
import 'dart:math';
import '../../../domain/models.dart';

class DailyTargets {
  final int calories;
  final double proteinG;
  final double carbG;
  final double fatG;
  final double bmi;
  final double bmr;
  final double tdee;
  final int age;

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

class NutritionCalc {
  // ---- IMC
  static double bmiKgCm({required double kg, required int heightCm}) {
    final h = max(0.001, heightCm / 100.0);
    return kg / (h * h);
  }

  // ---- Idade (anos) a partir de dateOfBirth (apenas data)
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

  static double tdeeFromBmr(double bmr, String activityLevel) {
    return bmr * activityFactor(activityLevel);
  }

  // ---- Ajuste calórico em função de peso-alvo e data-alvo (se houver)
  // regra prática: 1 kg ~ 7700 kcal
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
