# トビノリ

現在地から目的の駅までの最短経路情報のみを最速で提供する、個人利用向けの乗換アプリ。

## コンセプト

タイパ（タイムパフォーマンス）を追求し、「調べる → 確認する」までを最速にする。広告や余計な情報を削ぎ落とし、「現在地 → 目的の駅」を最速で調べられることに特化する。

## ドキュメント

- [要件定義書](docs/requirements.md)
- [アーキテクチャ設計・技術選定](docs/architecture.md)
- [開発ハーネス仕様書（エージェント構成・TDD/Gitワークフロー）](docs/development-harness.md)
- [デザインシステム](tobinori/stitch_/precision_transit_speed/DESIGN.md)

## 技術スタック

- Flutter（Dart） / Android・iOS対応（開発は Android 実機で確認）
- 状態管理: Riverpod（`flutter_riverpod`、コード生成なし）
- ローカルDB: `sqflite`（検索履歴の保存、クラウド同期なし）
- 位置情報: `geolocator`
- 経路検索: Google Maps Platform（Routes API）
- 最寄り駅までの徒歩ナビゲーション: Googleマップアプリへのインテント連携（アプリ内に独自地図UIは持たない）
- バックエンドレス構成（自前サーバー・認証機能なし）

詳細な選定理由は [docs/architecture.md](docs/architecture.md) を参照。

## 開発の進め方

- GitHub Issue単位（機能要件 F-01〜F-04）で実装を進める。
- 各Issueは「設計フェーズ（`design-issue`スキル）→ 実装フェーズ（`implement-issue`スキル）」の2段階で進める。
  - `design-issue`: ブランチ作成 → 詳細設計書作成 → 仕様の抜け漏れを自動レビュー → ユーザーとの対話で設計確定
  - `implement-issue`: 設計承認済みを前提に、TDD実装（Red → Green）→ 3種レビュー → （全指摘解消ゲート）→ コミット/PR
- `.claude/agents/` に実装・レビュー用のカスタムエージェントを用意している。
  - `flutter-detailed-design`: Issue単位の詳細設計書を作成
  - `detailed-design-review`: 詳細設計書の仕様抜け漏れを自動レビュー
  - `flutter-test-writer`: テスト作成（Red）
  - `flutter-feature-implementation`: 実装（Green）
  - `flutter-code-review`: コード品質・アーキテクチャ・セキュリティレビュー
  - `spec-compliance-review`: 要件定義書との仕様整合性レビュー
  - `flutter-ux-review`: UI/UXレビュー
- 詳細は [docs/development-harness.md](docs/development-harness.md) を参照。

## 開発体制

個人開発・個人利用。ストア配布は行わず、開発者自身の端末への直接インストールを想定。
