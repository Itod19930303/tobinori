import 'package:sqflite/sqflite.dart';
import 'package:tobinori/domain/history/record_search_history_usecase.dart';
import 'package:tobinori/domain/history/search_history_entry.dart';

/// 検索履歴の永続化。失敗時は例外をそのままthrowする。
///
/// 設計書: docs/design/issue-4-search-history.md 3.4節
abstract class SearchHistoryRepository {
  Future<List<SearchHistoryEntry>> findAll();
  Future<void> save(String stationName, {required int maxCount});
  Future<void> delete(int id);
  Future<void> deleteAll();
}

class SearchHistoryRepositoryImpl implements SearchHistoryRepository {
  SearchHistoryRepositoryImpl({
    required Future<Database> Function() openDatabase,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _openDatabase = openDatabase; // ignore: prefer_initializing_formals

  final Future<Database> Function() _openDatabase;
  final DateTime Function() _now;

  Future<Database>? _dbFuture;

  // 失敗したFutureはキャッシュせず、次回呼び出しで再オープンを試みる。
  Future<Database> _db() async {
    final cached = _dbFuture;
    if (cached != null) return cached;
    final future = _openDatabase();
    _dbFuture = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_dbFuture, future)) {
        _dbFuture = null;
      }
      rethrow;
    }
  }

  @override
  Future<List<SearchHistoryEntry>> findAll() async {
    final db = await _db();
    final rows = await db.query(
      'search_history',
      orderBy: 'searched_at DESC, id DESC',
      limit: kSearchHistoryMaxCount,
    );
    return rows
        .map(
          (r) => SearchHistoryEntry(
            id: r['id']! as int,
            stationName: r['station_name']! as String,
            searchedAt: DateTime.fromMillisecondsSinceEpoch(
              r['searched_at']! as int,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<void> save(String stationName, {required int maxCount}) async {
    final db = await _db();
    await db.transaction((txn) async {
      await txn.insert(
        'search_history',
        {
          'station_name': stationName,
          'searched_at': _now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.rawDelete(
        'DELETE FROM search_history WHERE id NOT IN '
        '(SELECT id FROM search_history ORDER BY searched_at DESC, id DESC LIMIT ?)',
        [maxCount],
      );
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db();
    await db.delete('search_history', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteAll() async {
    final db = await _db();
    await db.delete('search_history');
  }
}
