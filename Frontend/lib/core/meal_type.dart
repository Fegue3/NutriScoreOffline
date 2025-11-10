/// NutriScore — Tipos de Refeição (Core)
///
/// Enum e extensões utilitárias para representar os **slots de refeição** na app:
/// - `breakfast` (Pequeno-almoço)
/// - `lunch` (Almoço)
/// - `snack` (Lanche)
/// - `dinner` (Jantar)
///
/// Fornece:
/// - [MealTypeX.labelPt] — rótulo em PT-PT para UI;
/// - [MealTypeX.dbValue] — valor canónico para persistência/integração (DB/remote);
/// - [MealTypeX.fromPt] — parsing robusto a partir de *strings* em PT-PT.
///
/// Uso típico:
/// ```dart
/// final m = MealTypeX.fromPt('Almoço'); // -> MealType.lunch
/// print(m.dbValue);   // 'LUNCH'
/// print(m.labelPt);   // 'Almoço'
/// ```
enum MealType { breakfast, lunch, snack, dinner }

/// Extensões utilitárias para [MealType].
extension MealTypeX on MealType {
  /// Rótulo em **português de Portugal** para apresentação em UI.
  String get labelPt {
    switch (this) {
      case MealType.breakfast:
        return 'Pequeno-almoço';
      case MealType.lunch:
        return 'Almoço';
      case MealType.snack:
        return 'Lanche';
      case MealType.dinner:
        return 'Jantar';
    }
  }

  /// Valor canónico para persistência (ex.: base de dados, API).
  ///
  /// Mantém compatibilidade com esquemas/integrações que esperam
  /// *strings* em maiúsculas.
  String get dbValue {
    switch (this) {
      case MealType.breakfast:
        return 'BREAKFAST';
      case MealType.lunch:
        return 'LUNCH';
      case MealType.snack:
        return 'SNACK';
      case MealType.dinner:
        return 'DINNER';
    }
  }

  /// Converte um rótulo em PT-PT no respetivo [MealType].
  ///
  /// Aceita variações de caixa e espaços:
  /// - `'Pequeno-almoço'` → `breakfast`
  /// - `'Almoço'` → `lunch`
  /// - `'Lanche'` → `snack`
  /// - `'Jantar'` → `dinner`
  ///
  /// Caso não reconheça a *string*, devolve `MealType.breakfast` por defeito.
  static MealType fromPt(String s) {
    switch (s.trim().toLowerCase()) {
      case 'pequeno-almoço':
        return MealType.breakfast;
      case 'almoço':
        return MealType.lunch;
      case 'lanche':
        return MealType.snack;
      case 'jantar':
        return MealType.dinner;
      default:
        return MealType.breakfast;
    }
  }
}
