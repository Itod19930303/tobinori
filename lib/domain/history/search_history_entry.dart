/// 検索履歴1件を表す値オブジェクト。
///
/// 設計書: docs/design/issue-4-search-history.md 3.3節
class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.id,
    required this.stationName,
    required this.searchedAt,
  });

  final int id;

  /// 正規化済みの駅名（末尾「駅」なし）。
  final String stationName;
  final DateTime searchedAt;

  /// 一覧表示用の名前。末尾が「駅」でなければ「駅」を付ける。
  String get displayName =>
      stationName.endsWith('駅') ? stationName : '$stationName駅';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchHistoryEntry &&
        other.id == id &&
        other.stationName == stationName &&
        other.searchedAt == searchedAt;
  }

  @override
  int get hashCode => Object.hash(id, stationName, searchedAt);

  @override
  String toString() =>
      'SearchHistoryEntry(id: $id, stationName: $stationName, '
      'searchedAt: $searchedAt)';
}
