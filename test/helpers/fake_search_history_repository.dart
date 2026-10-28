// F-04 検索履歴のテストで共有する偽Repository。
//
// 設計書: docs/design/issue-4-search-history.md 7章「既存テストへの影響」
// `SearchScreen` / `TobinoriApp` を描画するテストは、実DB（sqflite）を使うと
// `MissingPluginException` になり `loadFailed` として静かに失敗するため、
// 必ず `searchHistoryRepositoryProvider` をこの偽物でoverrideすること。
import 'package:tobinori/data/history/search_history_repository.dart';
import 'package:tobinori/domain/history/search_history_entry.dart';

class FakeSearchHistoryRepository implements SearchHistoryRepository {
  FakeSearchHistoryRepository({List<SearchHistoryEntry> initial = const []})
      : entries = List.of(initial),
        _nextId = initial.fold<int>(
              0,
              (max, e) => e.id > max ? e.id : max,
            ) +
            1;

  /// 現在保持している履歴（新しい順）。
  List<SearchHistoryEntry> entries;
  int _nextId;

  /// 呼び出し記録。
  final List<String> savedNames = [];
  final List<int> savedMaxCounts = [];
  final List<int> deletedIds = [];
  int deleteAllCount = 0;
  int findAllCount = 0;

  /// 失敗させるフラグ。
  bool failFindAll = false;
  bool failSave = false;
  bool failDelete = false;
  bool failDeleteAll = false;

  /// 指定すると `findAll` の戻りをテスト側で制御できる（Completer用）。
  Future<List<SearchHistoryEntry>> Function()? onFindAll;

  @override
  Future<List<SearchHistoryEntry>> findAll() async {
    findAllCount++;
    if (failFindAll) {
      throw Exception('findAll failed');
    }
    final handler = onFindAll;
    if (handler != null) {
      return handler();
    }
    return List.of(entries);
  }

  @override
  Future<void> save(String stationName, {required int maxCount}) async {
    savedNames.add(stationName);
    savedMaxCounts.add(maxCount);
    if (failSave) {
      throw Exception('save failed');
    }
    entries = [
      SearchHistoryEntry(
        id: _nextId++,
        stationName: stationName,
        searchedAt: DateTime.now(),
      ),
      ...entries.where((e) => e.stationName != stationName),
    ];
    if (entries.length > maxCount) {
      entries = entries.sublist(0, maxCount);
    }
  }

  @override
  Future<void> delete(int id) async {
    deletedIds.add(id);
    if (failDelete) {
      throw Exception('delete failed');
    }
    entries = entries.where((e) => e.id != id).toList();
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCount++;
    if (failDeleteAll) {
      throw Exception('deleteAll failed');
    }
    entries = [];
  }
}

/// テスト用の履歴エントリ生成ヘルパー（idが大きいほど新しい）。
SearchHistoryEntry historyEntry(int id, String stationName) {
  return SearchHistoryEntry(
    id: id,
    stationName: stationName,
    searchedAt: DateTime.fromMillisecondsSinceEpoch(id * 1000),
  );
}
