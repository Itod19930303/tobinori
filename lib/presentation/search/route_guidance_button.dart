import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tobinori/domain/route/nearest_station.dart';
import 'package:tobinori/providers/route/route_guidance_provider.dart';

/// 最寄り駅までGoogleマップで徒歩案内を開始するボタン。
///
/// 設計書: docs/design/issue-3-route-guidance.md 3.1節
class RouteGuidanceButton extends ConsumerWidget {
  const RouteGuidanceButton({super.key, required this.station});

  final NearestStation station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLaunching = ref.watch(routeGuidanceProvider
        .select((s) => s.status == RouteGuidanceStatus.launching));

    ref.listen<RouteGuidanceState>(routeGuidanceProvider, (previous, next) {
      if (next.status == RouteGuidanceStatus.failed &&
          previous?.status != RouteGuidanceStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Googleマップを起動できませんでした')),
        );
      }
    });

    final label = '${station.name}まで徒歩で案内';
    // FilledButton自体がbutton/tap/enabledのセマンティクスを持ち、Textのラベルが
    // 読み上げ名になるため、Semanticsでラップしない（excludeSemanticsはtapを消す）。
    return FilledButton.icon(
      onPressed: isLaunching
          ? null
          : () =>
              ref.read(routeGuidanceProvider.notifier).startGuidance(station),
      icon: const Icon(Icons.directions_walk),
      label: Text(label),
    );
  }
}
