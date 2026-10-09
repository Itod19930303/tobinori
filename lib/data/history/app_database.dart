import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// アプリ共通のSQLiteデータベースを開く。
///
/// 設計書: docs/design/issue-4-search-history.md 3.4節
/// スキーマ変更時は`version`を上げて`onUpgrade`で対応する。
Future<Database> openAppDatabase() async {
  final dir = await getDatabasesPath();
  return openDatabase(
    p.join(dir, 'tobinori.db'),
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE search_history (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          station_name TEXT    NOT NULL UNIQUE,
          searched_at  INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_search_history_searched_at '
        'ON search_history (searched_at DESC)',
      );
    },
  );
}
