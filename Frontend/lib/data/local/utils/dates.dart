String canonDayUtcIso(DateTime dt) {
  final d = DateTime.utc(dt.year, dt.month, dt.day);
  return d.toIso8601String().replaceFirst('.000Z', 'Z');
}

String justDateIso(DateTime dt) {
  final d = DateTime.utc(dt.year, dt.month, dt.day);
  return d.toIso8601String().substring(0, 10);
}
