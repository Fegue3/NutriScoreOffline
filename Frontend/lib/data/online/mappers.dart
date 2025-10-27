import 'dart:convert';
import '../../domain/models.dart';
import 'dto.dart';

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

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

String? nutrimentsToJson(OffProductDto d) {
  final n = d.nutriments;
  if (n == null) return null;
  return jsonEncode(n);
}
