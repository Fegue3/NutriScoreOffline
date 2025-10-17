enum MealType { breakfast, lunch, snack, dinner }

extension MealTypeX on MealType {
  String get labelPt {
    switch (this) {
      case MealType.breakfast: return 'Pequeno-almoço';
      case MealType.lunch:     return 'Almoço';
      case MealType.snack:     return 'Lanche';
      case MealType.dinner:    return 'Jantar';
    }
  }
  String get dbValue {
    switch (this) {
      case MealType.breakfast: return 'BREAKFAST';
      case MealType.lunch:     return 'LUNCH';
      case MealType.snack:     return 'SNACK';
      case MealType.dinner:    return 'DINNER';
    }
  }

  static MealType fromPt(String s) {
    switch (s.trim().toLowerCase()) {
      case 'pequeno-almoço': return MealType.breakfast;
      case 'almoço':         return MealType.lunch;
      case 'lanche':         return MealType.snack;
      case 'jantar':         return MealType.dinner;
      default:               return MealType.breakfast;
    }
  }
}
