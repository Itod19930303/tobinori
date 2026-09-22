# 開発ハーネス仕様書 - トビノリ

本ドキュメントは、トビノリの実装フェーズにおける開発体制（カスタムエージェント構成・Git/GitHub運用・TDDワークフロー）をまとめたものである。要件定義（[docs/requirements.md](requirements.md)）・アーキテクチャ設計（[docs/architecture.md](architecture.md)）が確定した後の「実装の進め方」を定義する。

## 1. 全体フロー

Issue（機能要件単位）ごとに、**設計フェーズ**（`design-issue` スキル）と**実装フェーズ**（`implement-issue` スキル）の2段階で進める。

```
GitHub Issue（機能要件 F-XX）
   │
   ▼
┌─────────────── design-issue スキル ───────────────┐
│ ブランチ作成（main から issue-<番号>-<概要>）           │
│   │                                                │
│   ▼                                                │
│ ① flutter-detailed-design … 詳細設計書を作成            │
│   │                                                │
│   ▼                                                │
│ ② detailed-design-review … 仕様の抜け漏れを自動レビュー   │
│   （指摘があれば①②を自動で往復）                        │
│   │                                                │
│   ▼                                                │
│ ユーザーとの対話で設計を確定（＝設計承認）                 │
└─────────────────────────────────────────────────┘
   │
   ▼
┌─────────────── implement-issue スキル ─────────────┐
│（呼び出された時点で設計承認済みとみなして開始）             │
│   │                                                │
│   ▼                                                │
│ ③ flutter-test-writer  … テスト観点に基づき失敗するテストを先に書く（Red）│
│   │                                                │
│   ▼                                                │
│ ④ flutter-feature-implementation … テストを通す実装（Green）│
│   │                                                │
│   ▼                                                │
│（必要ならリファクタリング。テストが通り続けることを確認）      │
│   │                                                │
│   ▼                                                │
│ ⑤ flutter-code-review／⑥ spec-compliance-review／     │
│   ⑦ flutter-ux-review（画面がある場合）                 │
│   │                                                │
│   ▼                                                │
│【ゲート】重大な指摘がゼロになるまで、修正→再レビューを繰り返す │
│   （重大な指摘が残っている間はコミットしない）              │
│   │                                                │
│   ▼                                                │
│ コミット（末尾に #<issue番号>）→ push → PR作成（Closes #<issue番号>）│
└─────────────────────────────────────────────────┘
```

## 2. ワンコマンド実行（`design-issue` / `implement-issue` スキル）

- **`design-issue`**（`.claude/skills/design-issue/`）: 「issue #1の設計をして」のように依頼すると、ブランチ作成 → 詳細設計書の作成 → 自動レビュー（仕様の抜け漏れチェック）→ ユーザーとの対話による設計確定、までを進める。ここでのユーザーとの対話・合意が実質的な「設計承認」であり、明示的なゲートとしては設けず、対話そのものに承認プロセスを委ねる。
- **`implement-issue`**（`.claude/skills/implement-issue/`）: 「issue #1を実装して」のように依頼すると、TDD実装（Red→Green）→ 3種レビュー → コミット/push/PRまでを進める。**対応する詳細設計書が既に存在すること（＝`design-issue`で承認済みであること）を前提とし、このスキルが呼ばれたこと自体を設計承認済みとみなす**（設計書が存在しない場合は実装を進めず、先に`design-issue`を行うよう案内する）。
  - **レビュー通過ゲート**: 3種のレビューで「重大」な指摘が残っている間はコミットしない。修正・再レビューを指摘がなくなるまで繰り返す。

いずれのスキルも、各フェーズの節目でユーザーに状況を報告したうえで進める。「ワンコマンド＝無人で最後まで進む」という意味ではない。

## 3. カスタムエージェント一覧

すべて `.claude/agents/` 配下に定義。呼び出す際は、対応する作業内容（設計・テスト作成・実装・各種レビュー）を依頼すれば、該当エージェントが自動的に選択されるほか、エージェント名を明示して呼び出すこともできる。`design-issue`／`implement-issue` スキルを使う場合は、これらは自動的に順番通り呼び出される。

| エージェント名 | 役割 | 使用ツール | 呼び出しタイミング |
|---|---|---|---|
| `requirements-definition` | ヒアリング内容から要件定義書を構造化・更新 | Read, Write, Edit, Glob, Grep | 要件ヒアリング時（`requirements-definition` skillから呼び出し） |
| `architecture-tech-selection` | 要件定義書からアーキテクチャ設計・技術選定を実施 | Read, Write, Edit, Glob, Grep, WebSearch | 要件定義完了後、明示的に呼び出し |
| `flutter-detailed-design` | Issue単位の詳細設計書を作成（画面構成・クラス設計・状態遷移・API入出力・異常系・テスト観点） | Read, Write, Edit, Glob, Grep | `design-issue`スキルの最初に呼び出し |
| `detailed-design-review` | 詳細設計書が要件定義書・アーキテクチャ設計書に対して抜け漏れなく整合しているかを自動レビュー | Read, Glob, Grep | `design-issue`スキル内、設計書作成直後 |
| `flutter-test-writer` | TDDのRedフェーズ。詳細設計書のテスト観点に基づきテストを先に作成（ユニット・Widget） | Read, Write, Edit, Glob, Grep, Bash | `implement-issue`スキルの最初に呼び出し |
| `flutter-feature-implementation` | TDDのGreenフェーズ。既存の失敗テストを通す実装 | Read, Write, Edit, Glob, Grep, Bash, WebSearch | テスト作成後 |
| `flutter-code-review` | コード品質・アーキ整合性・Riverpodの使い方・セキュリティ（秘密情報/端末権限/インテント連携の値検証/ログ）・デザインシステム準拠（コード上の実装）・カバレッジをレビュー | Read, Glob, Grep, Bash | 実装後、コミット前 |
| `spec-compliance-review` | 実装が要件定義書の仕様通りかを照合（機能・非機能要件の充足、スコープ外機能の混入、独自解釈の検出） | Read, Glob, Grep, Bash | 実装後、コミット前 |
| `flutter-ux-review` | 実際の見た目・操作性（スクリーンショットベース）のUI/UXレビュー | Read, Glob, Grep | 画面実装後、実機/エミュレータで確認できる状態になった時点 |

### レビュー3種の役割分担（重複させない）

- **flutter-code-review**: コードの書き方・設計・セキュリティ
- **spec-compliance-review**: 要件定義書との「仕様」の一致
- **flutter-ux-review**: 実際に見える「UI/UX」の良し悪し

## 4. TDD・カバレッジ方針

- Red → Green → Refactor の順で進める。`flutter-test-writer` が先にテストを書き、`flutter-feature-implementation` はそのテストを通すことを目的に実装する。
- カバレッジ目標: **90%**（ただし一律ではない）
  - ドメイン層（UseCase/Service）・データ層（Repository）・状態管理層（Riverpod Provider/StateNotifier）: 90%以上
  - UI層（Widget）: 主要な表示分岐・操作のみ。数値目標は追わない
  - `main.dart`・単純な定数/テーマ定義ファイル等: 計測対象外
- カバレッジ確認コマンド:
  ```
  flutter test --coverage
  ```

## 5. Git / GitHub運用

### 4.1 リポジトリ

- リポジトリ: [github.com/Itod19930303/tobinori](https://github.com/Itod19930303/tobinori)（private）
- デフォルトブランチ: `main`

### 4.2 Issue

機能要件（F-01〜F-04）を1機能=1Issueの粒度で登録済み。

| Issue | 内容 |
|---|---|
| [#1](https://github.com/Itod19930303/tobinori/issues/1) | F-01 現在地取得 |
| [#2](https://github.com/Itod19930303/tobinori/issues/2) | F-02 目的駅検索・最短ルート表示 |
| [#3](https://github.com/Itod19930303/tobinori/issues/3) | F-03 最寄り駅までの経路案内 |
| [#4](https://github.com/Itod19930303/tobinori/issues/4) | F-04 検索履歴 |

着手順の目安: #1 → #2 → #3 → #4（F-02がF-01の現在地情報に依存するなど、機能間の依存関係を考慮）。

新規Issueを追加する場合のコマンド例:
```bash
gh issue create --title "F-XX 機能名" --body "概要・画面フロー・参照ドキュメント・TDDでの進め方を記載"
```

### 4.3 ブランチ運用

Issueごとに `main` からブランチを切る。命名規則: `issue-<Issue番号>-<内容を表す英語スラッグ>`

```bash
git checkout main
git pull
git checkout -b issue-1-current-location
```

### 4.4 コミットメッセージ

対応するIssue番号を末尾に含める。

```bash
git commit -m "現在地取得のテスト・実装を追加

#1"
```

### 4.5 プルリクエスト

実装・レビュー完了後、Issueに紐づくPRを作成しマージする。

```bash
git push -u origin issue-1-current-location
gh pr create --title "F-01 現在地取得" --body "Closes #1

## Summary
...

## Test plan
- [ ] flutter test --coverage
"
```

`Closes #1` と書くことで、PRマージ時に対応するIssueが自動でクローズされる。

## 6. 開発環境

- 実装言語・フレームワーク: Flutter（Dart）
- **現時点でこの開発機にはFlutter SDK未インストール**（2026-09-22時点、実装着手前のため保留中）
- バージョン管理方針: `fvm`（Flutter Version Management）でプロジェクト単位にFlutter SDKバージョンを固定する方針（導入は実装着手時に行う）
- コンテナ化（Docker）は採用しない
  - 理由: 実機（Android）でのUSBデバッグ・GPUアクセスとの相性が悪く、iOSビルドはmacOSが必須なためDockerでは解決できないこと、個人開発の規模でコンテナ化のメリットが薄いことから見送り。SDKバージョンの統一のみ`fvm`で対応する。

## 7. 今後のTODO

- [ ] Flutter SDK / `fvm` のセットアップ（実装着手時）
- [ ] `flutter create` によるプロジェクト初期化（`docs/architecture.md` のレイヤー構成に合わせたディレクトリ構成で作成）
- [ ] `implement-issue` スキルでIssue #1（F-01 現在地取得）からTDDで実装着手
