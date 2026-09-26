import 'package:flutter/material.dart';
import 'package:tobinori/domain/route/route.dart' as domain;

/// 成功時の最短ルート1件をカードUIで表示するWidget。
///
/// 設計書: docs/design/issue-2-station-search.md 4.1節
class RouteResultCard extends StatelessWidget {
  const RouteResultCard({super.key, required this.route});

  final domain.Route route;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '所要時間: ${route.totalDuration.inMinutes}分',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('乗換: ${route.transferCount}回', style: textTheme.bodyMedium),
            const Divider(height: 24),
            for (final step in route.steps) _RouteStepTile(step: step),
          ],
        ),
      ),
    );
  }
}

class _RouteStepTile extends StatelessWidget {
  const _RouteStepTile({required this.step});

  final domain.RouteStep step;

  @override
  Widget build(BuildContext context) {
    if (step.type == domain.RouteStepType.walk) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.directions_walk),
        title: Text('徒歩 ${step.duration.inMinutes}分'),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.train),
      title: Text(step.lineName ?? ''),
      subtitle: Text(
        '${step.headsign ?? ''}（${step.departureStopName ?? ''} → '
        '${step.arrivalStopName ?? ''}） ${step.duration.inMinutes}分',
      ),
    );
  }
}
