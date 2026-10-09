import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/data/history/app_database.dart';
import 'package:tobinori/data/history/search_history_repository.dart';
import 'package:tobinori/domain/history/record_search_history_usecase.dart';
import 'package:tobinori/domain/history/search_history_entry.dart';
import 'package:tobinori/providers/route/route_search_provider.dart';

/// 設計書: docs/design/issue-4-search-history.md 3.2節
final searchHistoryRepositoryProvider = Provider<SearchHistoryRepository>((
  ref,
) {
  return SearchHistoryRepositoryImpl(openDatabase: openAppDatabase);
});

final recordSearchHistoryUseCaseProvider =
    Provider<RecordSearchHistoryUseCase>(
  (ref) => RecordSearchHistoryUseCase(ref.watch(searchHistoryRepositoryProvider)),
);

enum SearchHistoryStatus { loading, loaded, loadFailed }

class SearchHistoryState {
  const SearchHistoryState({
    required this.status,
    this.entries = const [],
  });

  final SearchHistoryStatus status;
  final List<SearchHistoryEntry> entries;

  SearchHistoryState copyWith({
    SearchHistoryStatus? status,
    List<SearchHistoryEntry>? entries,
  }) {
    return SearchHistoryState(
      status: status ?? this.status,
      entries: entries ?? this.entries,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchHistoryState &&
        other.status == status &&
        listEquals(other.entries, entries);
  }

  @override
  int get hashCode => Object.hash(status, Object.hashAll(entries));

  @override
  String toString() => 'SearchHistoryState(status: $status, entries: $entries)';
}

class SearchHistoryNotifier extends StateNotifier<SearchHistoryState> {
  SearchHistoryNotifier(this._ref)
      : super(const SearchHistoryState(status: SearchHistoryStatus.loading)) {
    // 保存連携はF-04側で閉じる（RouteSearchNotifierは変更しない）。
    _ref.listen<RouteSearchState>(routeSearchProvider, (previous, next) {
      final query = next.lastQuery;
      if (previous?.status != RouteSearchStatus.success &&
          next.status == RouteSearchStatus.success &&
          query != null) {
        unawaited(_record(query));
      }
    });
    unawaited(load());
  }

  final Ref _ref;
  int _loadSeq = 0;

  Future<void> _record(String query) async {
    try {
      await _ref.read(recordSearchHistoryUseCaseProvider).call(query);
      await load();
    } catch (e) {
      // 駅名はログに出さない。
      debugPrint('検索履歴の保存に失敗しました: ${e.runtimeType}');
    }
  }

  Future<void> load() async {
    final seq = ++_loadSeq;
    try {
      final entries =
          await _ref.read(searchHistoryRepositoryProvider).findAll();
      if (!mounted || seq != _loadSeq) return;
      state = SearchHistoryState(
        status: SearchHistoryStatus.loaded,
        entries: entries,
      );
    } catch (e) {
      debugPrint('検索履歴の読み込みに失敗しました: ${e.runtimeType}');
      if (!mounted || seq != _loadSeq) return;
      state = state.copyWith(status: SearchHistoryStatus.loadFailed);
    }
  }

  Future<bool> remove(int id) async {
    try {
      await _ref.read(searchHistoryRepositoryProvider).delete(id);
    } catch (e) {
      debugPrint('検索履歴の削除に失敗しました: ${e.runtimeType}');
      return false;
    }
    await load();
    return true;
  }

  Future<bool> clear() async {
    try {
      await _ref.read(searchHistoryRepositoryProvider).deleteAll();
    } catch (e) {
      debugPrint('検索履歴の全件削除に失敗しました: ${e.runtimeType}');
      return false;
    }
    await load();
    return true;
  }
}

/// autoDisposeを使わず、一度生成されたらアプリ終了まで保存リスナーを維持する。
final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, SearchHistoryState>(
  (ref) => SearchHistoryNotifier(ref),
);
