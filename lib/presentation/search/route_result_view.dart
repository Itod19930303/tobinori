import 'package:flutter/material.dart';
import 'package:tobinori/presentation/search/route_guidance_button.dart';
import 'package:tobinori/presentation/search/route_result_card.dart';
import 'package:tobinori/providers/route/route_search_provider.dart';

/// `RouteSearchState`を受け取り、状態ごとに表示を出し分けるWidget。
///
/// 設計書: docs/design/issue-2-station-search.md 4.1節
/// `notFound`は`idle`と同じプレースホルダー表示を行う
/// （該当駅なしの通知は`SearchScreen`側のフラッシュメッセージで表示するため）。
class RouteResultView extends StatelessWidget {
  const RouteResultView({super.key, required this.state});

  final RouteSearchState state;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case RouteSearchStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case RouteSearchStatus.success:
        final route = state.route;
        if (route == null) {
          return _placeholder();
        }
        final nearestStation = route.nearestStation;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RouteResultCard(route: route),
              if (nearestStation != null) ...[
                const SizedBox(height: 16),
                RouteGuidanceButton(station: nearestStation),
              ],
            ],
          ),
        );
      case RouteSearchStatus.error:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '最短ルートを取得できませんでした。電波状況を確認し、再度検索してください。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      case RouteSearchStatus.idle:
      case RouteSearchStatus.notFound:
      case RouteSearchStatus.locationUnavailable:
      case RouteSearchStatus.offline:
        return _placeholder();
    }
  }

  Widget _placeholder() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('目的駅名を入力して検索してください'),
    );
  }
}
