// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
abstract class _$NutriDatabase extends GeneratedDatabase {
  _$NutriDatabase(QueryExecutor e) : super(e);
  $NutriDatabaseManager get managers => $NutriDatabaseManager(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [];
}

class $NutriDatabaseManager {
  final _$NutriDatabase _db;
  $NutriDatabaseManager(this._db);
}
