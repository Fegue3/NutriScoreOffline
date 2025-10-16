import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class LegacyHash {
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt::$password');
    final digest = sha256.convert(bytes).bytes;
    return '$salt\$${base64Url.encode(digest)}';
  }

  static bool verifyPassword(String password, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 2) return false;
    final salt = parts.first;
    final expected = hashPassword(password, salt);
    return expected == stored;
  }
}
