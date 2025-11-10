import 'dart:convert';
import 'package:crypto/crypto.dart';

/// NutriScore — LegacyHash (compatibilidade com hashes antigos)
///
/// Utilitário simples para **gerar e verificar** hashes de palavra-passe
/// compatíveis com um formato legado baseado em `SHA-256` + `salt`.
///
///
/// ### Formato do armazenado
/// `"{salt}\${base64url(sha256(salt + '::' + password))}"`
class LegacyHash {
  /// Gera o hash legado para [password] com o [salt] fornecido.
  ///
  /// Retorna uma *string* no formato:
  /// `salt + '$' + base64Url(sha256(salt + '::' + password))`
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt::$password');
    final digest = sha256.convert(bytes).bytes;
    return '$salt\$${base64Url.encode(digest)}';
  }

  /// Verifica se a [password] corresponde ao hash [stored] no formato legado.
  ///
  /// - Divide [stored] em `salt` e `hash` pelo separador `'$'`;
  /// - Recalcula com [hashPassword] e compara **string a string**.
  /// - Se o formato não cumprir `salt$hash`, devolve `false`.
  static bool verifyPassword(String password, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 2) return false;
    final salt = parts.first;
    final expected = hashPassword(password, salt);
    return expected == stored;
  }
}
