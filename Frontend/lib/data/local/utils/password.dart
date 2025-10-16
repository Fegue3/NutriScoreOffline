import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';

class PasswordCodec {
  static const int _iterations = 120000; // >=100k
  static const int _saltLen = 16;
  static const int _dkLen = 32; // 256-bit

  static String _randSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(_saltLen, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

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

  /// Guardado como: pbkdf2$iter$dkLen$saltB64$hashB64
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
