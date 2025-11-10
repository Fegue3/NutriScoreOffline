import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// NutriScore — Armazenamento Seguro (FlutterSecureStorage)
///
/// Wrapper simples sobre [FlutterSecureStorage] para guardar:
/// - **Sessão atual** (ID do utilizador autenticado);
/// - **Chave da base de dados** (planeada para uso futuro com SQLCipher).
///
/// Notas de segurança:
/// - Os valores são guardados no **Keychain/Keystore** da plataforma (iOS/Android);
/// - A geração de chaves usa `Random.secure()` com 256 bits (Base64 URL-safe);
/// - As *keys* internas têm versão no sufixo (`.v1`) para permitir migrações futuras.
class SecureStore {
  /// Chave do *secure storage* para o utilizador atual.
  static const _kCurrentUserId = 'nutriscore.current_user_id.v1';

  /// Chave do *secure storage* para a **DB key** (SQLCipher no futuro).
  static const _kDbKey = 'nutriscore.sqlcipher.key.v1'; // para futuro (ficheiro encriptado)

  /// Instância subjacente de armazenamento seguro.
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // ---------------------------------------------------------------------------
  // Sessão
  // ---------------------------------------------------------------------------

  /// Guarda o **ID do utilizador atual** (sessão).
  Future<void> saveCurrentUserId(String userId) =>
      _secure.write(key: _kCurrentUserId, value: userId);

  /// Lê o **ID do utilizador atual** (sessão), ou `null` se não existir.
  Future<String?> readCurrentUserId() =>
      _secure.read(key: _kCurrentUserId);

  /// Limpa a **sessão atual** (remove o ID do utilizador guardado).
  Future<void> clearSession() =>
      _secure.delete(key: _kCurrentUserId);

  // ---------------------------------------------------------------------------
  // Chave do DB (SQLCipher — planeado)
  // ---------------------------------------------------------------------------

  /// Obtém (ou cria) a **chave da base de dados** para encriptação futura.
  ///
  /// Fluxo:
  /// 1) Tenta ler `_kDbKey` do *secure storage*;
  /// 2) Se existir e não estiver vazia, devolve-a;
  /// 3) Caso contrário, gera **256 bits** com `Random.secure()`, codifica em
  ///    **Base64 URL-safe**, guarda e devolve.
  ///
  /// > Esta chave está preparada para futuras versões com **SQLCipher**.
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
