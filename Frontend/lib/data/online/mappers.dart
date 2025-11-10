import 'dart:convert';
import '../../domain/models.dart';
import 'dto.dart';

/// Utilitário: converte dinamicamente para `int?`.
/// Aceita `int`, `double`, `num` ou `String` (via `int.tryParse`).
int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Utilitário: converte dinamicamente para `double?`.
/// Aceita `num` diretamente ou `String` (via `double.tryParse`).
double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Mapeia um [OffProductDto] (DTO vindo do OFF) para o **modelo de domínio** [ProductModel].
///
/// Regras e cuidados:
/// - `id` fica vazio (`''`) para permitir que o repositório local gere um UUID se necessário;
/// - `name`: se vier vazio, utiliza o **barcode** como fallback (garante um nome não vazio);
/// - `brand` é normalizada com `trim()` (pode ser `null`);
/// - Nutrimentos:
///   - Energia procura primeiro `energy-kcal_100g`, depois `energy-kcal_100g_estimated`,
///     e por fim `energy-kcal` (alguns produtos antigos usam variantes);
///   - Hidratos aceita `carbohydrates_100g` ou o alias `carbs_100g`;
///   - Restantes campos seguem as chaves canónicas do OFF (`*_100g`).
ProductModel dtoToProductModel(OffProductDto d) {
  final n = d.nutriments ?? const {};

  return ProductModel(
    id: '', // será gerado pelo repositório local se necessário
    barcode: d.code,
    name: (d.name ?? '').trim().isEmpty ? d.code : d.name!.trim(),
    brand: d.brands?.trim(),
    energyKcal100g: _toInt(n['energy-kcal_100g'] ?? n['energy-kcal_100g_estimated'] ?? n['energy-kcal']),
    protein100g: _toDouble(n['proteins_100g']),
    carb100g: _toDouble(n['carbohydrates_100g'] ?? n['carbs_100g']),
    fat100g: _toDouble(n['fat_100g']),
    sugars100g: _toDouble(n['sugars_100g']),
    fiber100g: _toDouble(n['fiber_100g']),
    salt100g: _toDouble(n['salt_100g']),
  );
}

/// Serializa o bloco `nutriments` de um [OffProductDto] para JSON (`String`).
///
/// - Devolve `null` se `nutriments` for `null`;
/// - Caso exista, retorna `jsonEncode(n)` sem transformação adicional.
String? nutrimentsToJson(OffProductDto d) {
  final n = d.nutriments;
  if (n == null) return null;
  return jsonEncode(n);
}
