import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _kCurrentUserId = 'nutriscore.current_user_id.v1';
  static const _kDbKey = 'nutriscore.sqlcipher.key.v1'; // para futuro (ficheiro encriptado)

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // Sessão
  Future<void> saveCurrentUserId(String userId) =>
      _secure.write(key: _kCurrentUserId, value: userId);

  Future<String?> readCurrentUserId() =>
      _secure.read(key: _kCurrentUserId);

  Future<void> clearSession() =>
      _secure.delete(key: _kCurrentUserId);

  // Chave do DB (se ativares SQLCipher depois)
  Future<String> getOrCreateDbKey() async {
    final existing = await _secure.read(key: _kDbKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256)); // 256-bit
    final b64 = base64UrlEncode(bytes);
    await _secure.write(key: _kDbKey, value: b64);
    return b64;
  }
}
