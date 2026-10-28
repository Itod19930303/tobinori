import 'package:flutter/material.dart';

/// 目的駅名のテキスト入力欄＋検索ボタン。
///
/// 設計書: docs/design/issue-2-station-search.md 4.1節
class DestinationSearchField extends StatefulWidget {
  const DestinationSearchField({
    super.key,
    required this.onSubmit,
    required this.enabled,
    this.controller,
  });

  /// 未指定なら内部で生成・破棄する。指定時の破棄は呼び出し側の責務。
  final TextEditingController? controller;

  /// 送信時に呼び出されるコールバック（引数は入力された目的駅名）。
  final ValueChanged<String> onSubmit;

  /// オフライン中・現在地未取得中・検索リクエスト中はfalseにして送信不可にする。
  final bool enabled;

  @override
  State<DestinationSearchField> createState() =>
      _DestinationSearchFieldState();
}

class _DestinationSearchFieldState extends State<DestinationSearchField> {
  TextEditingController? _ownController;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.enabled) {
      return;
    }
    widget.onSubmit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              hintText: '目的の駅名を入力',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: widget.enabled ? (_) => _submit() : null,
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: widget.enabled ? _submit : null,
          style: ElevatedButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            disabledBackgroundColor:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
            disabledForegroundColor:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
          ),
          child: const Text('検索'),
        ),
      ],
    );
  }
}
