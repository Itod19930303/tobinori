// DestinationSearchField のWidgetテスト（F-04で追加したcontroller引数）。
//
// 設計書: docs/design/issue-4-search-history.md 3.1節・7章
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/presentation/search/destination_search_field.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    TextEditingController? controller,
    required List<String> submitted,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DestinationSearchField(
            controller: controller,
            enabled: enabled,
            onSubmit: submitted.add,
          ),
        ),
      ),
    );
  }

  group('controller未指定', () {
    testWidgets('従来どおり入力して検索ボタンで送信できること', (tester) async {
      final submitted = <String>[];
      await pumpField(tester, submitted: submitted);

      await tester.enterText(find.byType(TextField), '渋谷');
      await tester.tap(find.widgetWithText(ElevatedButton, '検索'));
      await tester.pump();

      expect(submitted, ['渋谷']);
    });
  });

  group('controller指定', () {
    testWidgets('外部コントローラの変更が入力欄に反映されること', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpField(tester, controller: controller, submitted: []);

      controller.text = '新宿';
      await tester.pump();

      expect(find.widgetWithText(TextField, '新宿'), findsOneWidget);
    });

    testWidgets('入力が外部コントローラに反映され、送信時にその値が渡ること', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final submitted = <String>[];
      await pumpField(tester, controller: controller, submitted: submitted);

      await tester.enterText(find.byType(TextField), '東京');
      await tester.tap(find.widgetWithText(ElevatedButton, '検索'));
      await tester.pump();

      expect(controller.text, '東京');
      expect(submitted, ['東京']);
    });

    testWidgets('Widget破棄後も外部コントローラは破棄されない（呼び出し側が破棄する）こと', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpField(tester, controller: controller, submitted: []);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // 破棄済みのコントローラを操作すると例外になる。
      expect(() => controller.text = 'ok', returnsNormally);
    });
  });
}
