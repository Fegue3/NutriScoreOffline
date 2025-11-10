/// NutriScore — Utilitários de Datas (local/utils/dates)
///
/// Funções auxiliares para normalizar datas em **UTC** e formatar *strings* ISO.
///
/// - [canonDayUtcIso] → devolve o **início do dia em UTC** em ISO-8601 completo,
///   sem milissegundos (`Z` no fim), ex.: `2025-11-10T00:00:00Z`.
/// - [justDateIso] → devolve apenas a **parte da data** em ISO-8601 (`YYYY-MM-DD`),
///   ex.: `2025-11-10`.
///
/// > Nota: Ambas as funções **ignoraram a hora local** e constroem um `DateTime.utc`
/// > com `year/month/day` — útil para chaves de dia canónicas em base de dados.
library;

/// Devolve a *string* ISO-8601 do **dia canónico em UTC** (às 00:00:00Z),
/// sem milissegundos.
///
/// Exemplo:
/// ```dart
/// final s = canonDayUtcIso(DateTime(2025, 11, 10, 18, 30)); // -> "2025-11-10T00:00:00Z"
/// ```
String canonDayUtcIso(DateTime dt) {
  final d = DateTime.utc(dt.year, dt.month, dt.day);
  return d.toIso8601String().replaceFirst('.000Z', 'Z');
}

/// Devolve apenas a data (`YYYY-MM-DD`) em ISO-8601, baseada no **dia UTC**.
///
/// Exemplo:
/// ```dart
/// final s = justDateIso(DateTime(2025, 11, 10, 18, 30)); // -> "2025-11-10"
/// ```
String justDateIso(DateTime dt) {
  final d = DateTime.utc(dt.year, dt.month, dt.day);
  return d.toIso8601String().substring(0, 10);
}
