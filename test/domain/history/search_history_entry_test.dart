// SearchHistoryEntry のユニットテスト。
//
// 設計書: docs/design/issue-4-search-history.md 3.3節・7章
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/history/search_history_entry.dart';

void main() {
  final searchedAt = DateTime.fromMillisecondsSinceEpoch(1000);

  SearchHistoryEntry build({
    int id = 1,
    String stationName = '新宿',
    DateTime? at,
  }) {
    return SearchHistoryEntry(
      id: id,
      stationName: stationName,
      searchedAt: at ?? searchedAt,
    );
  }

  group('displayName', () {
    test('「駅」で終わらない名前には「駅」が付くこと', () {
      expect(build(stationName: '新宿').displayName, '新宿駅');
    });

    test('既に「駅」で終わる名前には重ねて付かないこと', () {
      expect(build(stationName: '新宿駅').displayName, '新宿駅');
    });

    test('「駅」のみの名前は「駅」のままであること', () {
      expect(build(stationName: '駅').displayName, '駅');
    });
  });

  group('等価性', () {
    test('全フィールドが同じなら等しく、hashCodeも一致すること', () {
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });

    test('idが異なれば等しくないこと', () {
      expect(build(id: 1), isNot(build(id: 2)));
    });

    test('stationNameが異なれば等しくないこと', () {
      expect(build(stationName: '新宿'), isNot(build(stationName: '渋谷')));
    });

    test('searchedAtが異なれば等しくないこと', () {
      expect(
        build(),
        isNot(build(at: DateTime.fromMillisecondsSinceEpoch(2000))),
      );
    });

    test('toStringにstationNameが含まれること', () {
      expect(build().toString(), contains('新宿'));
    });
  });
}
