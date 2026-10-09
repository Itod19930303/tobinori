// SearchHistoryList / SearchHistoryTile のWidgetテスト。
//
// 設計書: docs/design/issue-4-search-history.md 3.1節・7章
//
// 【実装エージェントへの前提共有】
// - SearchHistoryList({super.key, required bool enabled,
//   required ValueChanged<String> onSelect, required VoidCallback onDeleteFailed})
//   （lib/presentation/search/search_history_list.dart）。
// - 履歴行のタイトルは displayName（例「新宿駅」）、onSelect には stationName（「新宿」）を渡す。
// - 「×」は tooltip「<displayName>を履歴から削除」のIconButton。
// - ヘッダーは「検索履歴」と「すべて削除」。確認ダイアログは AlertDialog で
//   「検索履歴をすべて削除しますか？」、ボタンは「キャンセル」「削除」。
// - 行タップ側のSemanticsラベルは「<displayName>を検索」（ラベルが他テキストと
//   結合されない完全一致で取得できること）。非活性時は isEnabled=false。
// - SnackBarは SearchHistoryList 自身は表示しない。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/domain/history/search_history_entry.dart';
import 'package:tobinori/presentation/search/search_history_list.dart';
import 'package:tobinori/providers/history/search_history_provider.dart';

import '../../helpers/fake_search_history_repository.dart';

void main() {
  late FakeSearchHistoryRepository repository;
  late List<String> selected;
  late int deleteFailedCount;

  setUp(() {
    repository = FakeSearchHistoryRepository(
      initial: [
        historyEntry(3, '東京'),
        historyEntry(2, '渋谷'),
        historyEntry(1, '新宿'),
      ],
    );
    selected = [];
    deleteFailedCount = 0;
  });

  Future<void> pumpList(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchHistoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SearchHistoryList(
              enabled: enabled,
              onSelect: selected.add,
              onDeleteFailed: () => deleteFailedCount++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder deleteButton(String displayName) =>
      find.byTooltip('$displayNameを履歴から削除');

  group('表示', () {
    testWidgets('履歴が新しい順に表示名（駅付き）で表示され、ヘッダーが出ること', (tester) async {
      await pumpList(tester);

      expect(find.text('検索履歴'), findsOneWidget);
      expect(find.text('すべて削除'), findsOneWidget);
      expect(find.text('東京駅'), findsOneWidget);
      expect(find.text('渋谷駅'), findsOneWidget);
      expect(find.text('新宿駅'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('東京駅')).dy,
        lessThan(tester.getTopLeft(find.text('新宿駅')).dy),
      );
      expect(find.byIcon(Icons.history), findsNWidgets(3));
    });

    testWidgets('0件のときは何も表示しないこと', (tester) async {
      repository = FakeSearchHistoryRepository();
      await pumpList(tester);

      expect(find.text('検索履歴'), findsNothing);
      expect(find.text('すべて削除'), findsNothing);
    });

    testWidgets('loadFailedのときは「履歴を読み込めませんでした」のみ表示されること', (tester) async {
      repository.failFindAll = true;
      await pumpList(tester);

      expect(find.text('履歴を読み込めませんでした'), findsOneWidget);
      expect(find.text('検索履歴'), findsNothing);
      expect(find.text('すべて削除'), findsNothing);
    });

    testWidgets('読み込み中（loading）は何も表示せずスピナーも出さないこと', (tester) async {
      final completer = Completer<List<SearchHistoryEntry>>();
      repository.onFindAll = () => completer.future;
      await pumpList(tester);

      expect(find.text('検索履歴'), findsNothing);
      expect(find.text('履歴を読み込めませんでした'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      completer.complete([]);
      await tester.pump();
    });

    testWidgets('非常に長い駅名は1行で省略表示されること', (tester) async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(1, '非常に長い駅名' * 20)],
      );
      await pumpList(tester);

      final text = tester.widget<Text>(find.textContaining('非常に長い駅名').first);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('行タップ', () {
    testWidgets('enabledのとき、行タップでonSelectに「駅」なしのstationNameが渡ること', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('新宿駅'));
      await tester.pump();

      expect(selected, ['新宿']);
    });

    testWidgets('enabled=falseのとき、行タップしてもonSelectが呼ばれないこと', (tester) async {
      await pumpList(tester, enabled: false);

      await tester.tap(find.text('新宿駅'), warnIfMissed: false);
      await tester.pump();

      expect(selected, isEmpty);
    });

    testWidgets('enabled=falseでも「×」で削除できること', (tester) async {
      await pumpList(tester, enabled: false);

      await tester.tap(deleteButton('新宿駅'));
      await tester.pumpAndSettle();

      expect(find.text('新宿駅'), findsNothing);
      expect(repository.deletedIds, [1]);
    });
  });

  group('Semantics（SearchHistoryTile）', () {
    testWidgets('行タップ側に「新宿駅を検索」のラベルがあり、活性時は有効であること', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester);

      final finder = find.bySemanticsLabel('新宿駅を検索');
      expect(finder, findsOneWidget);
      expect(
        tester.getSemantics(finder),
        isSemantics(hasEnabledState: true, isEnabled: true),
      );
      handle.dispose();
    });

    testWidgets('非活性時は無効として扱われること', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester, enabled: false);

      final finder = find.bySemanticsLabel('新宿駅を検索');
      expect(finder, findsOneWidget);
      expect(
        tester.getSemantics(finder),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });
  });

  group('1件削除（×）', () {
    testWidgets('「×」で該当行だけ消えること', (tester) async {
      await pumpList(tester);

      await tester.tap(deleteButton('渋谷駅'));
      await tester.pumpAndSettle();

      expect(find.text('渋谷駅'), findsNothing);
      expect(find.text('東京駅'), findsOneWidget);
      expect(find.text('新宿駅'), findsOneWidget);
      expect(repository.deletedIds, [2]);
      expect(deleteFailedCount, 0);
    });

    testWidgets('削除に失敗するとonDeleteFailedが1回呼ばれ、SnackBarは表示されず、行は残ること', (tester) async {
      repository.failDelete = true;
      await pumpList(tester);

      await tester.tap(deleteButton('渋谷駅'));
      await tester.pumpAndSettle();

      expect(deleteFailedCount, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('渋谷駅'), findsOneWidget);
    });
  });

  group('全件削除', () {
    Finder dialogButton(String label) => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(label),
        );

    testWidgets('「すべて削除」で確認ダイアログが表示されること', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('すべて削除'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('検索履歴をすべて削除しますか？'), findsOneWidget);
      expect(dialogButton('キャンセル'), findsOneWidget);
      expect(dialogButton('削除'), findsOneWidget);
    });

    testWidgets('キャンセルでは何も消えないこと', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('すべて削除'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('新宿駅'), findsOneWidget);
      expect(repository.deleteAllCount, 0);
    });

    testWidgets('ダイアログ表示中にリストが外れても「削除」で例外なく全件削除されること', (tester) async {
      final show = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchHistoryRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: show,
                builder: (_, visible, _) => visible
                    ? SearchHistoryList(
                        enabled: true,
                        onSelect: selected.add,
                        onDeleteFailed: () => deleteFailedCount++,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('すべて削除'));
      await tester.pumpAndSettle();
      show.value = false;
      await tester.pump();
      await tester.tap(dialogButton('削除'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repository.deleteAllCount, 1);
    });

    testWidgets('「削除」で全件消えること', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('すべて削除'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('削除'));
      await tester.pumpAndSettle();

      expect(repository.deleteAllCount, 1);
      expect(find.text('新宿駅'), findsNothing);
      expect(find.text('検索履歴'), findsNothing);
      expect(deleteFailedCount, 0);
    });

    testWidgets('全件削除に失敗するとonDeleteFailedが1回呼ばれ、SnackBarは表示されないこと', (tester) async {
      repository.failDeleteAll = true;
      await pumpList(tester);

      await tester.tap(find.text('すべて削除'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('削除'));
      await tester.pumpAndSettle();

      expect(deleteFailedCount, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('新宿駅'), findsOneWidget);
    });
  });
}
