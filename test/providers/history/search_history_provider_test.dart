// SearchHistoryNotifier（searchHistoryProvider）のユニットテスト。
//
// 設計書: docs/design/issue-4-search-history.md 3.2節・4章・7章
//
// 【実装エージェントへの前提共有】
// - ファイル: lib/providers/history/search_history_provider.dart
//   公開するもの: searchHistoryRepositoryProvider / recordSearchHistoryUseCaseProvider /
//   searchHistoryProvider / SearchHistoryStatus / SearchHistoryState / SearchHistoryNotifier
// - SearchHistoryState({required status, entries = const []}) 。
// - SearchHistoryNotifier(Ref ref)。コンストラクタ内で初回load()とref.listenを行う。
// - routeSearchProviderは本物のRouteSearchNotifierを継承したテスト用Notifierで
//   差し替え、stateを直接操作して遷移を再現する。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tobinori/application/connectivity/connectivity_status_provider.dart';
import 'package:tobinori/domain/history/search_history_entry.dart';
import 'package:tobinori/providers/history/search_history_provider.dart';
import 'package:tobinori/providers/route/route_search_provider.dart';

import '../../helpers/fake_search_history_repository.dart';

/// stateを外から直接設定できるテスト用のRouteSearchNotifier。
class _ControllableRouteSearchNotifier extends RouteSearchNotifier {
  _ControllableRouteSearchNotifier(super.ref);

  void emit(RouteSearchState next) => state = next;
}

void main() {
  late FakeSearchHistoryRepository repository;
  late ProviderContainer container;
  late _ControllableRouteSearchNotifier routeNotifier;

  ProviderContainer buildContainer() {
    final c = ProviderContainer(
      overrides: [
        searchHistoryRepositoryProvider.overrideWithValue(repository),
        connectivityStatusProvider.overrideWith(
          (ref) => Stream.value(ConnectivityStatus.online),
        ),
        routeSearchProvider.overrideWith((ref) {
          routeNotifier = _ControllableRouteSearchNotifier(ref);
          return routeNotifier;
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  SearchHistoryState historyState() => container.read(searchHistoryProvider);

  SearchHistoryNotifier historyNotifier() =>
      container.read(searchHistoryProvider.notifier);

  RouteSearchState success(String query) =>
      RouteSearchState(status: RouteSearchStatus.success, lastQuery: query);

  /// 履歴Providerを生成し、routeSearchProviderも確定させる。
  void start() {
    container = buildContainer();
    container.read(routeSearchProvider);
    container.read(searchHistoryProvider);
  }

  setUp(() {
    repository = FakeSearchHistoryRepository();
  });

  group('読み込み', () {
    test('生成直後はloadingで、読み込み完了後にloaded(entries)になること', () async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(2, '渋谷'), historyEntry(1, '新宿')],
      );
      start();

      expect(historyState().status, SearchHistoryStatus.loading);

      await pumpEventQueue();

      expect(historyState().status, SearchHistoryStatus.loaded);
      expect(historyState().entries.map((e) => e.stationName), ['渋谷', '新宿']);
    });

    test('履歴が空でもloadedで空リストになること', () async {
      start();
      await pumpEventQueue();

      expect(historyState().status, SearchHistoryStatus.loaded);
      expect(historyState().entries, isEmpty);
    });

    test('findAllが例外ならloadFailedになり、復帰後のload()でloadedに戻ること', () async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(1, '新宿')],
      )..failFindAll = true;
      start();
      await pumpEventQueue();

      expect(historyState().status, SearchHistoryStatus.loadFailed);

      repository.failFindAll = false;
      await historyNotifier().load();

      expect(historyState().status, SearchHistoryStatus.loaded);
      expect(historyState().entries.single.stationName, '新宿');
    });
  });

  group('検索成功時の保存', () {
    test('successへ遷移すると正規化済みの名前でsaveされ、再読み込みされること', () async {
      start();
      await pumpEventQueue();
      expect(repository.findAllCount, 1);

      routeNotifier.emit(success('新宿駅'));
      await pumpEventQueue();

      expect(repository.savedNames, ['新宿']);
      expect(repository.findAllCount, 2);
      expect(historyState().entries.map((e) => e.stationName), ['新宿']);
    });

    test('notFound / error / offline への遷移ではsaveされないこと', () async {
      start();
      await pumpEventQueue();

      routeNotifier.emit(
        const RouteSearchState(
          status: RouteSearchStatus.notFound,
          lastQuery: '存在しない',
        ),
      );
      await pumpEventQueue();
      routeNotifier.emit(
        const RouteSearchState(
          status: RouteSearchStatus.error,
          errorMessage: 'x',
          lastQuery: '新宿',
        ),
      );
      await pumpEventQueue();
      routeNotifier.emit(
        const RouteSearchState(
          status: RouteSearchStatus.offline,
          lastQuery: '新宿',
        ),
      );
      await pumpEventQueue();

      expect(repository.savedNames, isEmpty);
    });

    test('lastQueryがnullのsuccessではsaveされないこと', () async {
      start();
      await pumpEventQueue();

      routeNotifier.emit(const RouteSearchState(status: RouteSearchStatus.success));
      await pumpEventQueue();

      expect(repository.savedNames, isEmpty);
    });

    test('success → loading → success の再検索で2回目も保存されること', () async {
      start();
      await pumpEventQueue();

      routeNotifier.emit(success('新宿'));
      await pumpEventQueue();
      routeNotifier.emit(
        const RouteSearchState(
          status: RouteSearchStatus.loading,
          lastQuery: '渋谷',
        ),
      );
      await pumpEventQueue();
      routeNotifier.emit(success('渋谷'));
      await pumpEventQueue();

      expect(repository.savedNames, ['新宿', '渋谷']);
      expect(historyState().entries.map((e) => e.stationName), ['渋谷', '新宿']);
    });

    test('success のまま別のフィールドだけ変わっても二重に保存されないこと', () async {
      start();
      await pumpEventQueue();

      routeNotifier.emit(success('新宿'));
      await pumpEventQueue();
      routeNotifier.emit(success('新宿').copyWith(errorMessage: 'dummy'));
      await pumpEventQueue();

      expect(repository.savedNames, ['新宿']);
    });

    test('saveが例外をthrowしても例外が漏れず、状態が壊れないこと', () async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(1, '新宿')],
      )..failSave = true;
      start();
      await pumpEventQueue();

      routeNotifier.emit(success('渋谷'));
      await pumpEventQueue();

      expect(repository.savedNames, ['渋谷']);
      expect(historyState().status, SearchHistoryStatus.loaded);
      expect(historyState().entries.map((e) => e.stationName), ['新宿']);
    });

    test('購読者がいなくなっても保存リスナーが生きていること（autoDisposeでない）', () async {
      container = buildContainer();
      container.read(routeSearchProvider);
      final sub = container.listen(searchHistoryProvider, (_, _) {});
      await pumpEventQueue();
      sub.close();
      await pumpEventQueue();

      routeNotifier.emit(success('新宿'));
      await pumpEventQueue();

      expect(repository.savedNames, ['新宿']);
    });
  });

  group('remove / clear', () {
    test('removeが成功するとtrueを返し、再読み込みされること', () async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(2, '渋谷'), historyEntry(1, '新宿')],
      );
      start();
      await pumpEventQueue();

      final result = await historyNotifier().remove(2);

      expect(result, isTrue);
      expect(repository.deletedIds, [2]);
      expect(historyState().entries.map((e) => e.stationName), ['新宿']);
    });

    test('removeが失敗するとfalseを返し、状態は変わらないこと', () async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(2, '渋谷'), historyEntry(1, '新宿')],
      )..failDelete = true;
      start();
      await pumpEventQueue();
      final before = historyState();

      final result = await historyNotifier().remove(2);

      expect(result, isFalse);
      expect(historyState(), before);
    });

    test('clearが成功するとtrueを返し、空になること', () async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(2, '渋谷'), historyEntry(1, '新宿')],
      );
      start();
      await pumpEventQueue();

      final result = await historyNotifier().clear();

      expect(result, isTrue);
      expect(repository.deleteAllCount, 1);
      expect(historyState().status, SearchHistoryStatus.loaded);
      expect(historyState().entries, isEmpty);
    });

    test('clearが失敗するとfalseを返し、状態は変わらないこと', () async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(1, '新宿')],
      )..failDeleteAll = true;
      start();
      await pumpEventQueue();
      final before = historyState();

      final result = await historyNotifier().clear();

      expect(result, isFalse);
      expect(historyState(), before);
    });
  });

  group('読み込みのレース（連番トークン）', () {
    test('古いload()が後から完了しても、新しいload()の結果が最終stateになること', () async {
      final completers = <Completer<List<SearchHistoryEntry>>>[];
      repository = FakeSearchHistoryRepository()
        ..onFindAll = () {
          final c = Completer<List<SearchHistoryEntry>>();
          completers.add(c);
          return c.future;
        };
      start(); // 1回目のload()（生成時）
      await pumpEventQueue();
      final second = historyNotifier().load(); // 2回目
      await pumpEventQueue();
      expect(completers, hasLength(2));

      // 2回目を先に完了、1回目を後から完了させる。
      completers[1].complete([historyEntry(2, '新しい')]);
      await second;
      completers[0].complete([historyEntry(1, '古い')]);
      await pumpEventQueue();

      expect(historyState().status, SearchHistoryStatus.loaded);
      expect(historyState().entries.map((e) => e.stationName), ['新しい']);
    });

    test('保存後のload()が遅れて完了しても、削除後の内容に収束すること', () async {
      repository = FakeSearchHistoryRepository(
        initial: [historyEntry(1, '新宿')],
      );
      final pending = <(Completer<List<SearchHistoryEntry>>, List<SearchHistoryEntry>)>[];
      repository.onFindAll = () {
        // 呼び出し時点のDB内容を控え、完了のタイミングはテスト側で制御する。
        final c = Completer<List<SearchHistoryEntry>>();
        pending.add((c, List.of(repository.entries)));
        return c.future;
      };
      start();
      await pumpEventQueue();
      pending[0].$1.complete(pending[0].$2); // 初回load()を完了
      await pumpEventQueue();

      routeNotifier.emit(success('渋谷')); // save → L1（保存後 [渋谷, 新宿]）
      await pumpEventQueue();
      expect(pending, hasLength(2));

      final savedId = repository.entries.first.id;
      final removing = historyNotifier().remove(savedId); // delete → L2（[新宿]）
      await pumpEventQueue();
      expect(pending, hasLength(3));

      // L2を先に、L1を後に完了させる。
      pending[2].$1.complete(pending[2].$2);
      await removing;
      pending[1].$1.complete(pending[1].$2);
      await pumpEventQueue();

      expect(historyState().entries.map((e) => e.stationName), ['新宿']);
    });

    test('Notifier破棄後にload()が完了しても例外にならないこと', () async {
      final completer = Completer<List<SearchHistoryEntry>>();
      repository = FakeSearchHistoryRepository()
        ..onFindAll = () => completer.future;
      start();
      await pumpEventQueue();

      container.dispose();
      completer.complete([historyEntry(1, '新宿')]);
      await pumpEventQueue();
    });
  });

  group('SearchHistoryState', () {
    test('等価性とcopyWithが成り立つこと', () {
      const a = SearchHistoryState(status: SearchHistoryStatus.loading);
      const b = SearchHistoryState(status: SearchHistoryStatus.loading);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a.copyWith(status: SearchHistoryStatus.loaded).status,
        SearchHistoryStatus.loaded,
      );
      expect(a.copyWith(status: SearchHistoryStatus.loaded), isNot(a));
    });
  });
}
