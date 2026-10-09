import 'package:tobinori/data/history/search_history_repository.dart';
import 'package:tobinori/domain/history/station_name_normalizer.dart';

/// 履歴の保存件数上限。
const int kSearchHistoryMaxCount = 20;

/// 検索成功した駅名を履歴に記録する。
///
/// 設計書: docs/design/issue-4-search-history.md 3.3節
class RecordSearchHistoryUseCase {
  RecordSearchHistoryUseCase(this._repository);

  final SearchHistoryRepository _repository;

  Future<void> call(String rawStationName) async {
    final name = normalizeStationName(rawStationName);
    if (name.isEmpty) {
      return;
    }
    await _repository.save(name, maxCount: kSearchHistoryMaxCount);
  }
}
