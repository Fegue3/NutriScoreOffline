import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// NutriScore — Codificação de Palavras-passe (PBKDF2-HMAC-SHA256)
///
/// Implementa **hashing seguro de palavras-passe** com PBKDF2/HMAC-SHA256,
/// *salt* aleatório e iterações elevadas, seguindo boas práticas modernas.
///
/// ### Formato de armazenamento
/// A *string* persistida segue o esquema:
///
/// `pbkdf2$<iter>$<dkLen>$<saltB64url>$<hashB64url>`
///
/// Onde:
/// - `iter`: número de iterações PBKDF2 (>= 100k);
/// - `dkLen`: tamanho, em bytes, da chave derivada (ex.: 32 para 256-bit);
/// - `saltB64url`: *salt* aleatório codificado em **Base64 URL-safe**;
/// - `hashB64url`: *digest* PBKDF2 codificado em **Base64 URL-safe**.
///
/// ### Notas de segurança
/// - Usa **Random.secure()** para o *salt*.
/// - Comparação do *digest* feita em laço constante (best-effort) para reduzir
///   *timing side-channels*.
/// - Recomenda-se rever periodicamente o parâmetro de **iterações** conforme
///   a evolução de hardware/ameaças.
/// - Para migrações, guardar o formato como acima para permitir *re-hashing*
///   transparente no futuro.
class PasswordCodec {
  /// Número de iterações PBKDF2 (padrão ≥ 100k).
  static const int _iterations = 120000; // >=100k

  /// Tamanho do *salt* em bytes.
  static const int _saltLen = 16;

  /// Tamanho da chave derivada (*derived key*) em bytes (256-bit).
  static const int _dkLen = 32; // 256-bit

  /// Gera um *salt* aleatório (Base64 URL-safe).
  static String _randSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(_saltLen, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Implementação local de PBKDF2/HMAC-SHA256.
  ///
  /// Parâmetros:
  /// - [password]: bytes da palavra-passe;
  /// - [salt]: bytes do *salt*;
  /// - [iter]: número de iterações;
  /// - [dkLen]: comprimento do *output* desejado.
  ///
  /// Retorna os primeiros [dkLen] bytes do bloco PBKDF2.
  static List<int> _pbkdf2(List<int> password, List<int> salt, int iter, int dkLen) {
    final hmac = (List<int> key, List<int> msg) => Hmac(sha256, key).convert(msg).bytes;
    final blockLen = sha256.convert(const [0]).bytes.length; // 32
    final blockCount = (dkLen / blockLen).ceil();
    final out = BytesBuilder();

    for (int i = 1; i <= blockCount; i++) {
      final iBytes = ByteData(4)..setUint32(0, i);
      var u = hmac(password, [...salt, ...iBytes.buffer.asUint8List()]);
      final t = List<int>.from(u);
      for (int j = 1; j < iter; j++) {
        u = hmac(password, u);
        for (int k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      out.add(t);
    }
    final res = out.toBytes();
    return res.sublist(0, dkLen);
  }

  /// Gera o **hash PBKDF2** para a [password] fornecida.
  ///
  /// - Cria um *salt* aleatório;
  /// - Deriva a chave com PBKDF2/HMAC-SHA256;
  /// - Devolve a *string* no formato: `pbkdf2$iter$dkLen$saltB64$hashB64`.
  ///
  /// Exemplo:
  /// ```dart
  /// final stored = PasswordCodec.hash('minhaSenhaForte!');
  /// ```
  ///
  /// Guardado como: `pbkdf2$iter$dkLen$saltB64$hashB64`
  static String hash(String password) {
    final saltB64 = _randSalt();
    final salt = base64Url.decode(saltB64);
    final dk = _pbkdf2(utf8.encode(password), salt, _iterations, _dkLen);
    final dh = base64UrlEncode(dk);

    // constrói a string manualmente, muito mais limpo
    return 'pbkdf2\$'
        '$_iterations\$'
        '$_dkLen\$'
        '$saltB64\$'
        '$dh';
  }

  /// Verifica se a [password] corresponde ao hash [stored] no formato PBKDF2.
  ///
  /// Passos:
  /// 1. Valida o prefixo `pbkdf2` e estrutura com 5 partes separadas por `$`;
  /// 2. Extrai `iter`, `dkLen`, `salt` e `hash` (Base64 URL-safe);
  /// 3. Recalcula PBKDF2 com os mesmos parâmetros;
  /// 4. Compara tamanhos e bytes em laço constante (*best-effort*).
  ///
  /// Retorna `true` se coincidir, `false` caso contrário (inclui erros de parsing).
  static bool verify(String password, String stored) {
    try {
      // dividir pelo '$' literal
      final parts = stored.split(r'$'); // ou stored.split('\$')
      if (parts.length != 5 || parts[0] != 'pbkdf2') return false;

      final iter = int.parse(parts[1]);
      final dkLen = int.parse(parts[2]);
      final salt = base64Url.decode(parts[3]);
      final expected = base64Url.decode(parts[4]);

      final dk = _pbkdf2(utf8.encode(password), salt, iter, dkLen);
      if (dk.length != expected.length) return false;

      // comparação byte-a-byte para reduzir *timing leaks*
      var same = true;
      for (int i = 0; i < dk.length; i++) {
        same &= (dk[i] == expected[i]);
      }
      return same;
    } catch (_) {
      return false;
    }
  }
}
