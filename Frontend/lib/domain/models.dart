/// Modelos de **domínio** do NutriScore.
/// -----------------------------------------------------------------------------
/// Estes tipos representam o núcleo de dados usados pela app (independentes de
/// storage/local ou APIs remotas). São estruturas simples, imutáveis, sem
/// dependências de UI ou de bibliotecas externas (além do SDK Dart).
///
/// Boas práticas seguidas:
/// - Campos `final` e construtores `const` onde possível;
/// - Tipos e *nullability* explícitos (p. ex., `String? brand`);
/// - Comentários a clarificar unidades/formatos (kcal, g, ISO 8601, etc.).
library;
// -----------------------------------------------------------------------------

class UserModel {
  /// Identificador interno do utilizador (UUID).
  final String id;

  /// Email normalizado (lowercase).
  final String email;

  /// Nome opcional.
  final String? name;

  const UserModel({required this.id, required this.email, this.name});
}

/// Metas e perfis do utilizador para cálculo de objetivos nutricionais.
class UserGoalsModel {
  /// ID do utilizador (chave estrangeira para `User`).
  final String userId;

  /// Sexo biológico: `'MALE' | 'FEMALE' | 'OTHER'`.
  final String sex;

  /// Data de nascimento (apenas data; sem horas).
  final DateTime? dateOfBirth;

  /// Altura em centímetros.
  final int heightCm;

  /// Peso atual em quilogramas.
  final double currentWeightKg;

  /// Peso-alvo em quilogramas (0 quando não definido).
  final double targetWeightKg;

  /// Data-alvo para atingir o objetivo de peso (opcional).
  final DateTime? targetDate;

  /// Nível de atividade: `'sedentary' | 'light' | 'moderate' | 'active' | 'very_active'`.
  final String activityLevel;

  /// Calorias diárias alvo (se `null`, podem ser calculadas pelo serviço).
  final int? dailyCalories;

  /// Percentagens de macros (devem somar 100; podem ser `null` → usar *defaults*).
  final int? carbPercent;
  final int? proteinPercent;
  final int? fatPercent;

  const UserGoalsModel({
    required this.userId,
    required this.sex,
    required this.dateOfBirth,
    required this.heightCm,
    required this.currentWeightKg,
    required this.targetWeightKg,
    required this.targetDate,
    required this.activityLevel,
    this.dailyCalories,
    this.carbPercent,
    this.proteinPercent,
    this.fatPercent,
  });
}

/// Produto alimentar normalizado para a app (fonte: local ou OFF).
class ProductModel {
  /// ID interno (UUID), pode vir vazio quando o repositório o gera.
  final String id;

  /// Código de barras (barcode) do produto.
  final String barcode;

  /// Nome apresentado. Quando desconhecido, pode usar o `barcode` como *fallback*.
  final String name;

  /// Marca (opcional).
  final String? brand;

  /// Energia por 100g (kcal), quando disponível.
  final int? energyKcal100g;

  /// Macronutrientes por 100g (gramas), quando disponíveis.
  final double? protein100g, carb100g, fat100g, sugars100g, fiber100g, salt100g;

  const ProductModel({
    required this.id,
    required this.barcode,
    required this.name,
    this.brand,
    this.energyKcal100g,
    this.protein100g,
    this.carb100g,
    this.fat100g,
    this.sugars100g,
    this.fiber100g,
    this.salt100g,
  });
}

/// Uma refeição de um dia com os respetivos itens e totais agregados.
class MealWithItems {
  /// ID da refeição.
  final String id;

  /// Tipo da refeição: `'BREAKFAST' | 'LUNCH' | 'DINNER' | 'SNACK'`.
  final String type;

  /// Dia **canónico UTC** (ISO 8601, apenas data).
  final String dateIso;

  /// Total de calorias da refeição (kcal).
  final int totalKcal;

  /// Totais de macros da refeição (g).
  final double protein, carb, fat;

  /// Itens pertencentes a esta refeição.
  final List<MealItemModel> items;

  const MealWithItems({
    required this.id,
    required this.type,
    required this.dateIso,
    required this.totalKcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.items,
  });
}

/// Item de refeição (produto ou alimento personalizado) com quantidades e totais.
class MealItemModel {
  /// ID do item (UUID).
  final String id;

  /// ID da refeição a que pertence.
  final String mealId;

  /// Se o item corresponde a um **produto** de catálogo, contém o `barcode`.
  final String? productBarcode;

  /// Se o item corresponde a um **alimento personalizado**, contém o respetivo ID.
  final String? customFoodId;

  /// Nome resumido para UI (opcional; pode vir da origem).
  final String? name;

  /// Marca (apenas para produtos), opcional.
  final String? brand;

  /// Unidade usada para a quantidade: `'GRAM' | 'ML' | 'PIECE'`.
  final String unit;

  /// Quantidade na unidade escolhida (ex.: 30 g, 200 ml, 1 peça).
  final double quantity;

  /// Total em gramas resultante (pode ser calculado a partir de `unit`/densidade).
  final double? gramsTotal;

  /// Totais nutricionais **do item** (após multiplicar pela quantidade).
  final int? kcal;
  final double? protein, carb, fat, sugars, fiber, salt;

  const MealItemModel({
    required this.id,
    required this.mealId,
    this.productBarcode,
    this.customFoodId,
    this.name,
    this.brand,
    required this.unit,
    required this.quantity,
    this.gramsTotal,
    this.kcal,
    this.protein,
    this.carb,
    this.fat,
    this.sugars,
    this.fiber,
    this.salt,
  });
}

/// Estatísticas agregadas **por dia** para o utilizador.
class DailyStatsModel {
  /// ID do utilizador.
  final String userId;

  /// Dia em ISO 8601 (YYYY-MM-DD), canónico UTC.
  final String dateIso;

  /// Total de calorias (kcal) consumidas no dia.
  final int kcal;

  /// Totais de macros e micronutrientes relevantes (gramas) no dia.
  final double protein, carb, fat, sugars, fiber, salt;

  const DailyStatsModel({
    required this.userId,
    required this.dateIso,
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.sugars,
    required this.fiber,
    required this.salt,
  });
}

/// Registo de peso (um ou mais por dia). Usado para gráficos e metas.
class WeightLogModel {
  /// Dia em formato `YYYY-MM-DD` (sem horas).
  final String dayIso;

  /// Peso em quilogramas.
  final double kg;

  const WeightLogModel({required this.dayIso, required this.kg});
}

/// Pedido de inserção/atualização de um **item de refeição**.
///
/// Nota: `dayUtcCanon` deve vir como o *dia canónico UTC* (00:00 UTC),
/// garantindo consistência ao agrupar por dia.
class AddMealItemInput {
  /// ID do utilizador.
  final String userId;

  /// Dia canónico em UTC (meia-noite UTC).
  final DateTime dayUtcCanon;

  /// Tipo da refeição: `'BREAKFAST' | 'LUNCH' | 'DINNER' | 'SNACK'`.
  final String mealType;

  /// Barcode do produto (quando aplicável).
  final String? productBarcode;

  /// ID de alimento personalizado (quando aplicável).
  final String? customFoodId;

  /// Unidade de quantidade: `'GRAM' | 'ML' | 'PIECE'`.
  final String unit;

  /// Quantidade conforme a unidade indicada.
  final double quantity;

  const AddMealItemInput({
    required this.userId,
    required this.dayUtcCanon,
    required this.mealType,
    this.productBarcode,
    this.customFoodId,
    required this.unit,
    required this.quantity,
  });
}

/// ===== NOVOS: modelos para Histórico =====

/// Entrada apresentada na **listagem do histórico** de produtos consultados/scaneados.
class HistoryEntry {
  /// Identificador do registo (na BD é AUTOINCREMENT; aqui guardado como `String`).
  final String id;

  /// Barcode do produto (se conhecido).
  final String? barcode;

  /// Timestamp ISO 8601 de quando foi consultado/scaneado.
  final String scannedAtIso;

  /// Nutrientes resumidos (quando capturados no momento).
  final int? calories;
  final double? proteins, carbs, fat;

  /// Nome do produto (se existir na tabela `Product`).
  final String? name;

  /// Marca (se existir).
  final String? brand;

  const HistoryEntry({
    required this.id,
    required this.barcode,
    required this.scannedAtIso,
    this.calories,
    this.proteins,
    this.carbs,
    this.fat,
    this.name,
    this.brand,
  });
}

/// **Snapshot mínimo** para registar no histórico (payload de inserção).
class HistorySnapshot {
  /// Barcode do produto (obrigatório).
  final String barcode;

  /// Nome (opcional) capturado no momento.
  final String? name;

  /// Marca (opcional).
  final String? brand;

  /// Calorias e macronutrientes (opcionais) capturados no momento.
  final int? calories;
  final double? proteins, carbs, fat;

  const HistorySnapshot({
    required this.barcode,
    this.name,
    this.brand,
    this.calories,
    this.proteins,
    this.carbs,
    this.fat,
  });
}
