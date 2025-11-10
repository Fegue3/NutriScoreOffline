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

/// NutriScore — Repositório de Utilizadores (SQLite/Drift)
///
/// Gestão de **autenticação e conta local**:
/// - **Iniciar sessão** com verificação de palavra-passe (PBKDF2);
/// - **Migração automática** de hashes legados (`salt$sha256(...)`) para PBKDF2,
///   no primeiro login bem-sucedido;
/// - **Registar** novo utilizador com hash PBKDF2;
/// - Obter **utilizador atual** (via [SecureStore]);
/// - **Terminar sessão** e **apagar conta** (limpeza de dados + segredos).
class UserRepoSqlite implements UserRepo {
  /// Base de dados local (Drift/SQLite).
  final NutriDatabase db;

  /// Armazenamento seguro para sessão/segredos.
  final SecureStore secure;

  /// Constrói o repositório de utilizadores.
  UserRepoSqlite(this.db, this.secure);

  /// Acesso direto ao `FlutterSecureStorage` para um **deleteAll()** opcional
  /// (limpeza de todos os segredos do dispositivo).
  FlutterSecureStorage get _secureStorage => const FlutterSecureStorage();

  /// Normaliza emails: `trim().toLowerCase()`.
  String _norm(String e) => e.trim().toLowerCase();

  // ---------------------------------------------------------------------------
  // AUTENTICAÇÃO
  // ---------------------------------------------------------------------------

  /// Inicia sessão com [email] e [password].
  ///
  /// Fluxo:
  /// 1) Procura utilizador por `email` (case-insensitive);
  /// 2) Tenta validar o hash:
  ///    - Primeiro com **PBKDF2** ([PasswordCodec.verify]);
  ///    - Se falhar e detetar formato legado (`salt$hash`), valida com
  ///      [legacy.LegacyHash.verifyPassword]; em caso de sucesso **migra**
  ///      para PBKDF2 atualizando `passwordHash`;
  /// 3) Se válido, guarda `userId` no [SecureStore] e devolve [UserModel];
  /// 4) Caso contrário, devolve `null`.
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

  /// Cria uma nova conta de utilizador.
  ///
  /// - Gera `id` (UUID v4);
  /// - Faz hash PBKDF2 da [password];
  /// - Insere em `User` e guarda o `userId` no [SecureStore];
  /// - Devolve o `userId`.
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

  /// Devolve o **utilizador atual** (se existir sessão persistida).
  ///
  /// Lê o `userId` do [SecureStore] e carrega `id/email/name` da tabela `User`.
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

  /// Apaga **definitivamente** a conta do utilizador atualmente autenticado.
  ///
  /// Passos:
  /// - Obtém `userId` do [SecureStore]; se `null`, não faz nada;
  /// - Executa `DELETE FROM User WHERE id=?` numa **transação**, com `PRAGMA foreign_keys = ON;`
  ///   para garantir *cascades* se definidas no schema;
  /// - Limpa a sessão no [SecureStore];
  /// - (Opcional) faz `_secureStorage.deleteAll()` para limpar todos os segredos
  ///   do dispositivo (não obrigatório).
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

    //limpar TODOS os segredos do device (não é obrigatório)
    try {
      await _secureStorage.deleteAll();
    } catch (_) {}
  }

  /// Termina a sessão local (remove `current_user_id` do armazenamento seguro).
  @override
  Future<void> signOut() => secure.clearSession();
}
