// normalizeStationName のユニットテスト。
//
// 設計書: docs/design/issue-4-search-history.md 3.3節・7章
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/history/station_name_normalizer.dart';

void main() {
  group('normalizeStationName', () {
    test('「駅」なしの名前はそのまま返ること', () {
      expect(normalizeStationName('新宿'), '新宿');
    });

    test('末尾の「駅」が除去されること', () {
      expect(normalizeStationName('新宿駅'), '新宿');
    });

    test('前後の半角空白が除去されること', () {
      expect(normalizeStationName('  新宿  '), '新宿');
    });

    test('前後の全角スペースが除去されること', () {
      expect(normalizeStationName('　新宿駅　'), '新宿');
    });

    test('空白除去の後に末尾の「駅」が除去されること', () {
      expect(normalizeStationName(' 渋谷駅 '), '渋谷');
    });

    test('「駅」のみの場合は空にならないよう「駅」のまま返ること', () {
      expect(normalizeStationName('駅'), '駅');
      expect(normalizeStationName(' 駅 '), '駅');
    });

    test('途中にある「駅」は除去されないこと', () {
      expect(normalizeStationName('駅前'), '駅前');
    });

    test('空文字は空文字を返すこと', () {
      expect(normalizeStationName(''), '');
    });

    test('空白のみは空文字を返すこと', () {
      expect(normalizeStationName(' 　 '), '');
    });
  });
}
