import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';

// wrapper que já estás a usar para sessão/segredos
import 'secure_store.dart';

// password hashing PBKDF2 + migração sha256 antiga
import 'utils/password.dart';
import 'utils/legacy_hash.dart' as legacy;

// opcional – para limpar segredos se quiseres além do SecureStore
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;

class UserRepoSqlite implements UserRepo {
  final NutriDatabase db;
  final SecureStore secure;

  UserRepoSqlite(this.db, this.secure);

  // só para um último “deleteAll()” se quiseres varrer segredos
  FlutterSecureStorage get _secureStorage => const FlutterSecureStorage();

  String _norm(String e) => e.trim().toLowerCase();

  // ---------------------------------------------------------------------------

  @override
  Future<UserModel?> signIn(String email, String password) async {
    final rows = await db
        .customSelect(
          'SELECT id, email, name, passwordHash FROM User WHERE lower(email)=lower(?) LIMIT 1;',
          variables: [Variable.withString(_norm(email))],
        )
        .get();

    if (rows.isEmpty) return null;
    final r = rows.first.data;
    final stored = r['passwordHash'] as String;

    // 1) PBKDF2
    var ok = PasswordCodec.verify(password, stored);

    // 2) migração automática do legacy salt$sha256(...) -> PBKDF2
    if (!ok && stored.contains(r'$') && !stored.startsWith('pbkdf2\$')) {
      try {
        final legacyOk = legacy.LegacyHash.verifyPassword(password, stored);
        if (legacyOk) {
          final newHash = PasswordCodec.hash(password);
          await db.customStatement(
            "UPDATE User SET passwordHash=?, updatedAt=datetime('now') WHERE id=?;",
            [newHash, r['id']],
          );

          ok = true;
        }
      } catch (_) {
        // ignora
      }
    }

    if (!ok) return null;

    final model = UserModel(
      id: r['id'] as String,
      email: r['email'] as String,
      name: r['name'] as String?,
    );

    await secure.saveCurrentUserId(model.id);
    return model;
  }

  @override
  Future<String> signUp(String email, String password, {String? name}) async {
    final id = const Uuid().v4();
    final hash = PasswordCodec.hash(password);

    await db.customStatement(
      "INSERT INTO User (id, email, passwordHash, name, createdAt, updatedAt) "
      "VALUES (?, ?, ?, ?, datetime('now'), datetime('now'));",
      [id, _norm(email), hash, name],
    );

    await secure.saveCurrentUserId(id);
    return id;
  }

  @override
  Future<UserModel?> currentUser() async {
    final id = await secure.readCurrentUserId();
    if (id == null) return null;

    final rows = await db
        .customSelect(
          'SELECT id, email, name FROM User WHERE id=? LIMIT 1;',
          variables: [Variable.withString(id)],
        )
        .get();

    if (rows.isEmpty) return null;
    final r = rows.first.data;
    return UserModel(
      id: r['id'] as String,
      email: r['email'] as String,
      name: r['name'] as String?,
    );
  }

  @override
  Future<void> deleteAccount() async {
    // vai buscar o utilizador atual ao SecureStore (não uses _kCurrentUserKey)
    final id = await secure.readCurrentUserId();
    if (id == null) return;

    // garantir FK ON dentro da transação
    await db.transaction(() async {
      await db.customStatement('PRAGMA foreign_keys = ON;');
      await db.customStatement('DELETE FROM User WHERE id = ?;', [id]);
    });

    // limpar sessão local
    await secure.clearSession();

    // opcional: limpar TODOS os segredos do device (não é obrigatório)
    try {
      await _secureStorage.deleteAll();
    } catch (_) {}
  }

  @override
  Future<void> signOut() => secure.clearSession();
}
