# 詳細設計書 - Issue #2 F-02 目的駅検索・最短ルート表示

## 用語メモ

この設計書を読むうえで前提となる用語を簡単に補足する。

- **Riverpod**: Flutterで状態管理を行うためのライブラリ。画面の状態（検索中・成功・失敗など）を`Provider`という単位で管理する。
- **Provider**: Riverpodにおける「状態の入れ物」。用途によって`StateNotifierProvider`（更新可能な状態を持つ）、`StreamProvider`（外部からの継続的な通知を状態にする）などの種類がある。
- **UseCase**: ドメイン層（ビジネスロジック層）に置く、1つの機能単位の処理をまとめたクラス。本設計書では「現在地と駅名から最短ルートを検索する」処理を`SearchRouteUseCase`としてまとめている。
- **Repository**: 外部API・端末機能・ローカルDBなど「アプリの外部」とのやり取りを1箇所に集約するクラス。UseCase側は「Repositoryの向こう側がAPIなのかDBなのか」を意識しなくてよくする役割を持つ。
- **sealed class**: Dartの言語機能。とりうる型（状態）をあらかじめ列挙しておくことで、コンパイラが「分岐の考慮漏れ」を検出しやすくするしくみ。本設計書では簡易的な`enum`＋データクラスの組み合わせを採用し、`sealed class`は採用しない（3.2参照）。
- **二重送信ガード**: ユーザーが同じ操作（ここでは検索ボタン押下）を短時間に連続して行っても、リクエストが重複して発生しないようにする対策。

## 1. 対象Issue・関連要件
- Issue: #2 F-02 目的駅検索・最短ルート表示（https://github.com/Itod19930303/tobinori/issues/2）
- 関連する機能要件:
  - F-02（requirements.md 4章）: 目的駅名を入力して最短経路を検索・表示する。画面/操作フロー: 駅名入力 → 外部乗換案内API（Google Maps Platform Routes API）へ検索リクエスト → 最短ルート結果を表示。
  - F-01（requirements.md 4章）: 現在地取得。F-02はF-01が取得した現在地を検索の起点（origin）として利用する依存関係がある。
- 関連する非機能要件:
  - パフォーマンス（requirements.md 5章）: 「調べる→確認する」を最速に。Routes APIへのタイムアウトは短く（architecture.md 8.1で3〜5秒目安）設定し、応答がなければ即座にオフライン/エラー表示へ切り替える。
  - オフライン対応（requirements.md 5章、architecture.md 8.2）: オフライン・劣化時は自動フォールバックせず「オフライン中です」等を明示表示。新規検索は行わない。
  - セキュリティ（requirements.md 5章、architecture.md 8.3）: Google Maps Platform APIキーはコードに直書きせず `--dart-define-from-file` 経由で注入し、API制限（Routes APIのみ）・アプリケーション制限をGoogle Cloud Console側で設定する。
  - 外部連携（requirements.md 6章、architecture.md 6.1）: Google Maps Platform Routes API（`computeRoutes`、transitモード）を採用。構造化JSONを取得し独自デザインのカードUIで表示する。

## 2. 前提・依存関係（Issue #1 との連携）

F-02はF-01（現在地取得）が提供する現在地情報を検索起点（origin）として利用する。Issue #1の詳細設計書（`docs/design/issue-1-current-location.md`）で以下のインターフェースが確定済みであり、本設計書はこれに準拠する。

- `LocationRepository.getCurrentLocation() : Future<LocationResult>`（`Position`や独自`LatLng`ではなく、F-01で定義された`LocationResult`/`LocationPoint`を用いる）
- `currentLocationProvider`: `StateNotifierProvider<CurrentLocationNotifier, LocationState>`。状態は`LocationState`（`LocationInitial`/`LocationLoading`/`LocationLoaded(LocationPoint point)`/`LocationFailed(LocationFailureReason reason)`のsealed class）。
- `currentLocationPointProvider`: `Provider<LocationPoint?>`。`currentLocationProvider`が`LocationLoaded`の場合はその`LocationPoint`を、それ以外（`LocationInitial`/`LocationLoading`/`LocationFailed`）は`null`を返す派生Provider。
- `LocationPoint`（値オブジェクト）: `final double latitude; final double longitude;`

F-02は「取得済みの現在地だけを素直に使いたい」ケースに合致するため、`currentLocationProvider`を直接`watch`するのではなく、**`currentLocationPointProvider`（`LocationPoint?`）を検索起点の取得に利用する**方針とする（4.2章・5章参照）。

- 本設計書の4.2/4.3/4.4で登場する `currentLocationProvider` / `currentLocationPointProvider` / `LocationRepository` は、F-02のスコープでは**新規作成しない**（F-01のスコープ）。F-02側はこれらを`ref.watch`または引数として参照するのみとする疎結合設計とする。

## 3. 画面/UIフロー概要

```
[検索画面 SearchScreen]
  ┌───────────────────────────────┐
  │ (オフライン時のみ) オフラインバナー   │
  ├───────────────────────────────┤
  │ 目的駅名入力欄 [_______________] [検索]│
  ├───────────────────────────────┤
  │ 検索結果表示エリア                  │
  │  - 未検索: プレースホルダー（案内文）   │
  │  - ローディング中: スピナー           │
  │  - 成功: 最短ルートカード             │
  │      (所要時間 / 乗換駅 / 徒歩区間)   │
  │  - 該当駅なし: 検索結果エリアは直前の │
  │    表示（プレースホルダー等）のまま   │
  │  - エラー: 「取得できませんでした」＋再試行 │
  └───────────────────────────────┘
  ※ 該当駅なしの場合は画面上部にフラッシュメッセージ（一時的な通知）
    「該当する駅が見つかりませんでした」を表示する（下記4参照）
```

操作フロー:
1. アプリ起動時（F-01）に現在地取得を試行。並行してオフライン判定（`connectivity_plus`）を開始する。
2. ユーザーが目的駅名入力欄にテキストを入力し、「検索」ボタン押下（またはソフトウェアキーボードの検索/Enter）で送信する。
3. 送信時点で下記のいずれかに該当する場合は、API呼び出しを行わずにガード（4章・6章参照）。
   - オフライン状態
   - 現在地未取得（取得中／取得失敗）
   - 入力が空文字（または空白のみ）
4. ガードに該当しなければ、現在地（origin）と入力駅名（destination）を用いてRoutes APIへリクエストする。
5. レスポンスを最短ルート1件のドメインモデルへ変換し、結果カードに表示する。
6. 該当駅なしの場合は画面上部にフラッシュメッセージ（一時的な通知）で「該当する駅が見つかりませんでした」を表示する。入力欄の値はクリアせず保持し、ユーザーがそのまま入力を修正して再検索できるようにする（結果表示エリア自体は検索結果カードを表示しない＝直前の表示を維持し、通知は数秒で自動的に消える一般的なフラッシュメッセージの挙動に従う）。APIエラーの場合はエラー状態表示に切り替える。

## 4. クラス設計

### 4.1 UI層（Widget）

- **`SearchScreen`**（`lib/presentation/search/search_screen.dart`）
  - 責務: 検索画面全体のレイアウト。`ConsumerWidget`。`routeSearchProvider`と`connectivityStatusProvider`をwatchし、状態に応じて子Widgetを出し分ける。`routeSearchProvider`が`notFound`へ遷移したことを`ref.listen`で検知し、画面上部にフラッシュメッセージ（`SnackBar`等の一時的な通知）で「該当する駅が見つかりませんでした」を表示する（結果表示エリアの出し分けとは別に、通知として一度きり表示する）。
  - 主要な子Widget: `OfflineBanner`, `DestinationSearchField`, `RouteResultView`

- **`OfflineBanner`**（`lib/presentation/common/offline_banner.dart`）
  - 責務: `connectivityStatusProvider`がオフラインの時のみ表示する固定バナー（「オフライン中です」）。F-01/F-03/F-04からも共通利用される想定の共有Widget。
  - プロパティ: なし（Provider watchのみ）

- **`DestinationSearchField`**（`lib/presentation/search/destination_search_field.dart`）
  - 責務: 目的駅名のテキスト入力欄＋検索ボタン。入力値は`TextEditingController`で保持し、送信時に`routeSearchProvider.notifier.search(destinationName: ...)`を呼び出すコールバックを発火する。
  - 主要なプロパティ/コールバック: `onSubmit(String destinationName)`、`enabled`（オフライン中・現在地未取得中（`currentLocationPointProvider`が`null`）・検索リクエスト中（`loading`）はfalseにして送信不可にする。`loading`中を含めるのは二重送信ガードのため）

- **`RouteResultView`**（`lib/presentation/search/route_result_view.dart`）
  - 責務: `RouteSearchState`を受け取り、状態（idle/loading/success/error/locationUnavailable）ごとに表示を出し分けるSwitcher的Widget。`notFound`はこのWidget内では専用の表示を持たず、`idle`と同じプレースホルダー表示を行う（該当駅なしの通知は`SearchScreen`側のフラッシュメッセージで一度きり表示するため、3章参照）。
  - プロパティ: `RouteSearchState state`

- **`RouteResultCard`**（`lib/presentation/search/route_result_card.dart`）
  - 責務: 成功時の最短ルート1件をデザインシステムのカードUIで表示（総所要時間、乗換回数、区間リスト＝徒歩／電車の路線名・行き先）。
  - プロパティ: `Route route`（4.3のドメインモデル）

### 4.2 状態管理層（Riverpod Provider）

- **`routeSearchProvider`**
  - 型: `StateNotifierProvider<RouteSearchNotifier, RouteSearchState>`
  - 保持する状態: `RouteSearchState`（5章「状態遷移」参照）。
    `sealed class`や`freezed`は使わず、シンプルな`enum RouteSearchStatus`＋`RouteSearchState`データクラスの組み合わせを採用する。
    `RouteSearchState { status, route?, errorMessage?, lastQuery? }`
  - 責務:
    - 検索実行のトリガーを受け取る。
    - `SearchRouteUseCase`を呼び出す。
    - 結果に応じて状態を遷移させる。
    - `currentLocationPointProvider`・`connectivityStatusProvider`を参照し、送信可否を判定する。
  - **二重送信ガード**: `status`が`loading`の間は、`search()`が呼ばれても新しいリクエストを発行しない（早期return）。あわせてUI側（`DestinationSearchField`）も`loading`中は入力欄・検索ボタンを非活性にし、操作自体をできないようにする（多重にガードする）。

- **`connectivityStatusProvider`**
  - 型: `StreamProvider<ConnectivityStatus>`（`connectivity_plus`の`onConnectivityChanged`をラップ。`ConnectivityStatus { online, offline }`）
  - 保持する状態: 現在のオンライン/オフライン状態
  - 責務: architecture.md 8.2の「オフライン状態を一元管理するProvider」。F-02で最初に必要になるためこのIssueで新規作成するが、F-01/F-03/F-04からも共通利用される共有インフラProviderとして`lib/application/connectivity/`配下に配置する。
  - **レイヤー配置についての設計判断**: architecture.mdの全体構成図（1章）では「オンライン・オフライン判定」をドメイン層の責務として位置づけている。
    これは、architecture.md 8.2にある通り「接続状態の監視」と「API呼び出し自体の成否」の両方を合わせて広義の「オンライン・オフライン判定」と呼んでいるためであり、本設計ではこの2つを意図的に以下のように分離する。
    - **「接続断＝offline」**: `connectivity_plus`による端末の接続状態そのものの監視。これは外部サービスとの通信ロジックを含まない、単純なストリームの中継（値の変換のみ）であるため、`connectivityStatusProvider`として**状態管理層（Riverpod）に留める**。
    - **「オンラインだがAPI失敗＝error」**: Routes API呼び出しの成否判定。これは`SearchRouteUseCase`と`RouteRepository`（ドメイン層・データ層）が例外（`RouteApiException`等）として表現し、`RouteSearchNotifier`（状態管理層）がその例外を`error`状態へマッピングする。
    - まとめると、「接続の有無」という端末レベルの単純な監視はNotifier内に留め、「API呼び出しの成否判定」というビジネスロジックはドメイン層（UseCase/Repository）に置く、という役割分担にする。
      `connectivityStatusProvider`自体は分岐判定ロジックを持たず値を中継するだけなので、独立したドメインサービスとして切り出すほどの複雑さがない（個人開発規模で過剰な抽象化を避ける方針、requirements.md/development-harness.mdの方針にも合致する）ため、状態管理層に留める判断とした。
    - 両者が絡み合うケース（検索中に接続が切れる等）の具体的な振る舞いは5章の状態遷移・7章の異常系一覧を参照。

- **（依存・参照のみ）`currentLocationPointProvider`**: F-01側で定義される確定済みProvider（2章参照）。F-02では`ref.watch`で参照するのみ。検索起点（origin）は`currentLocationPointProvider`（`LocationPoint?`）から取得する。

### 4.3 ドメイン層（UseCase/Service）

- **`SearchRouteUseCase`**（`lib/domain/route/search_route_usecase.dart`）
  - シグネチャ: `Future<Route> call({required LocationPoint origin, required String destinationStationName})`（`origin`はF-01で定義された`LocationPoint`値オブジェクトを利用する）
  - 責務: 入力バリデーション（trim後の空文字チェックは呼び出し元Notifierで実施済み前提）、`RouteRepository.computeRoute()`の呼び出し、取得結果が0件の場合は`RouteNotFoundException`をthrow、通信失敗時は`RouteApiException`をthrowする。ビジネスロジックとしては「最短1件のみを返す」（Routes APIへのリクエスト時点で`computeAlternativeRoutes: false`を指定し複数ルート取得自体を行わない）。

- **ドメイン例外**（`lib/domain/route/route_exceptions.dart`）
  - `RouteNotFoundException`: 該当する駅・ルートが見つからない場合
  - `RouteApiException`: API呼び出し失敗（通信エラー、タイムアウト、5xx、想定外レスポンス形式）

- **ドメインモデル**（`lib/domain/route/route.dart`）
  - `Route { Duration totalDuration, int transferCount, List<RouteStep> steps }`
  - `RouteStep { RouteStepType type (walk/transit), String? lineName, String? headsign, String? departureStopName, String? arrivalStopName, Duration duration }`

### 4.4 データ層（Repository）

- **`RouteRepository`（インターフェース）/ `RouteRepositoryImpl`**（`lib/data/route/route_repository.dart`）
  - シグネチャ: `Future<Route?> computeRoute({required LocationPoint origin, required String destinationStationName})`
    - 戻り値`null`は「該当ルートなし」を表し、`SearchRouteUseCase`側で`RouteNotFoundException`に変換する（Repository層ではHTTP/JSONの都合のみを扱い、ドメイン例外への変換はUseCase側に寄せる）。
  - アクセス先: Google Maps Platform Routes API（`POST https://routes.googleapis.com/directions/v2:computeRoutes`）。`http`パッケージ（またはdio）でHTTPS通信。
    タイムアウトは5秒に設定し、`TimeoutException`は`RouteApiException`へラップしてthrowする。
    architecture.md 8.1では目安を3〜5秒としているが、本設計ではその上限である5秒を採用した。
    理由は、Routes APIは乗換経路の探索という比較的重い処理であり、電波状況が良くても3秒程度で確実に応答が返る保証がないため。
    タイムアウトを短くしすぎると、実際は成功していたはずの検索を誤って失敗扱いにしてしまう（ユーザー体験を損ねる）リスクの方を重く見た。
  - APIキーは`--dart-define-from-file`で注入された値をコンストラクタ引数または設定クラス経由で受け取る（コード直書き禁止）。

- **（依存・参照のみ）`LocationRepository`**: F-01側で定義される確定済みインターフェース（2章参照）。F-02のRepository層からは直接参照しない（現在地取得は`currentLocationPointProvider`経由で状態管理層から行う）。

## 5. 状態遷移

`RouteSearchState.status`（`enum RouteSearchStatus`）の遷移:

| 状態 | 説明 | 遷移条件 |
|---|---|---|
| `idle` | 初期状態／未検索 | 画面初期表示時。またはオフライン復帰時（`offline`から）でユーザーがまだ再検索していない場合 |
| `loading` | 検索リクエスト中。入力欄・検索ボタンは非活性（二重送信ガード） | `idle`/`success`/`notFound`/`error`の状態で、入力が空でなく・オンライン・現在地取得済みの条件を満たして送信された場合 |
| `success` | 最短ルート取得成功 | `loading`中に`SearchRouteUseCase`が`Route`を返した場合 |
| `notFound` | 該当駅・ルートが見つからない。画面上部にフラッシュメッセージを表示するのみで、結果表示エリアは`idle`同様のプレースホルダーのまま（3章参照） | `loading`中に`RouteNotFoundException`が発生した場合 |
| `error` | API通信エラー（オンラインだが失敗） | `loading`中に`RouteApiException`が発生した場合（タイムアウト含む） |
| `locationUnavailable` | 現在地が未取得（取得中／取得失敗） | 送信操作時に`currentLocationPointProvider`が`null`の場合。送信自体をガードしUI上はボタン非活性＋案内文表示 |
| `offline` | オフライン状態 | `connectivityStatusProvider`が`offline`を検知した時点で、他のどの状態からでも遷移。新規検索は送信不可（ボタン非活性） |

備考:
- `offline`と`locationUnavailable`は同時に発生しうる。
  この場合、UI表示上は「オフライン」を優先して表示する。
  理由は、ユーザーにとって「まず何が原因で使えないのか」を理解しやすくするため。
  現在地取得も結局オフラインでは失敗しやすく、根本原因はネットワーク接続であることが多い。
  （優先度判定のテストケースは8章「ガード系」を参照）
- `offline`から接続復帰した場合は`idle`へ戻す。
  自動再検索はしない（ユーザーが改めて検索操作を行う）。
- `loading`中は入力欄・検索ボタンを非活性にする（二重送信ガード）。
  ユーザーが検索ボタンを連打しても、追加のリクエストは発生しない。

## 6. 外部連携の詳細

### 6.1 Google Maps Platform Routes API（`computeRoutes`）

- エンドポイント: `POST https://routes.googleapis.com/directions/v2:computeRoutes`
- ヘッダー:
  - `Content-Type: application/json`
  - `X-Goog-Api-Key: <MAPS_API_KEY>`（`--dart-define-from-file`経由で注入）
  - `X-Goog-FieldMask`: レスポンスを必要最小限に絞りコストを抑える。例: `routes.duration,routes.legs.steps.transitDetails,routes.legs.steps.travelMode,routes.legs.steps.staticDuration,routes.legs.steps.navigationInstruction`
- リクエストボディ（例）:
  ```json
  {
    "origin": { "location": { "latLng": { "latitude": <現在地緯度>, "longitude": <現在地経度> } } },
    "destination": { "address": "<入力された駅名>駅" },
    "travelMode": "TRANSIT",
    "computeAlternativeRoutes": false,
    "languageCode": "ja",
    "unitSystem": "METRIC"
  }
  ```
  - 駅名入力値の末尾に「駅」を付与してから`address`として渡すことで検索精度を上げる（既に「駅」を含む入力の場合は重複しないよう末尾一致チェックを行う）。
- レスポンス構造（想定・簡略化）:
  ```json
  {
    "routes": [
      {
        "duration": "1234s",
        "legs": [
          {
            "steps": [
              { "travelMode": "WALK", "staticDuration": "180s", "navigationInstruction": {...} },
              { "travelMode": "TRANSIT", "staticDuration": "600s", "transitDetails": {
                  "stopDetails": { "departureStop": {"name": "..."}, "arrivalStop": {"name": "..."} },
                  "transitLine": { "name": "...", "vehicle": {...} },
                  "headsign": "..."
                }
              }
            ]
          }
        ]
      }
    ]
  }
  ```
  - `routes`配列が空、または`routes[0]`が存在しない場合を「該当ルートなし」と判定し`RouteRepository.computeRoute`は`null`を返す。
- ドメインモデルへのマッピング方針:
  - `routes[0].duration`（秒文字列）→ `Route.totalDuration`（`Duration`）
  - `legs[0].steps[]` → `Route.steps`（`travelMode == "WALK"` → `RouteStepType.walk`、`"TRANSIT"` → `RouteStepType.transit`。`transitDetails.transitLine.name`・`stopDetails.departureStop.name`・`stopDetails.arrivalStop.name`・`headsign`をそれぞれマッピング）
  - `Route.transferCount` → `steps`中の`transit`区分の出現回数 − 1（0未満にならないよう補正）

### 6.2 現在地情報（F-01からの入力）

- `SearchRouteUseCase.call()`の`origin`引数として、F-01が提供する`currentLocationPointProvider`（`LocationPoint?`）の値をそのまま利用する。F-02側での緯度経度の再取得・キャッシュは行わない（都度`currentLocationPointProvider`の最新値を利用し、送信操作時に`null`であれば4.2/5章の通り`locationUnavailable`としてガードする）。

## 7. 異常系・エッジケース一覧

| # | ケース | 検知方法 | 振る舞い |
|---|---|---|---|
| 1 | 目的駅名が空文字／空白のみ | 送信前にUI側でtrim後の長さチェック | 検索ボタンを非活性化、またはボタン押下時にAPIを呼ばずインラインエラー表示（「駅名を入力してください」）。API呼び出しは発生させない |
| 2 | オフライン状態で検索操作 | `connectivityStatusProvider`が`offline` | 検索ボタン非活性＋`OfflineBanner`表示。新規検索は行わない（8.2方針通り） |
| 3 | 検索中にオフラインへ遷移（通信途中で切断） | Routes API呼び出しがタイムアウト／`SocketException`等 | `RouteApiException`として捕捉し、`connectivityStatusProvider`の値も踏まえて`offline`状態へ遷移させる（オンラインのままAPIだけ失敗した場合は`error`状態） |
| 4 | 現在地が未取得（取得中・取得失敗） | `currentLocationPointProvider`が`null`（`currentLocationProvider`が`LocationLoading`/`LocationFailed`の場合） | `locationUnavailable`状態。検索ボタン非活性＋「現在地を取得できませんでした」等の案内表示 |
| 5 | 該当する駅・ルートが見つからない | Routes APIレスポンスの`routes`が空、または`NOT_FOUND`相当のエラーステータス | `notFound`状態。画面上部にフラッシュメッセージ（一時的な通知）で「該当する駅が見つかりませんでした」を表示。結果表示エリアは直前の表示（プレースホルダー等）を維持し、入力欄の値もクリアしない（そのまま再入力・再検索できるようにする）。クラッシュさせない |
| 6 | Routes APIがタイムアウト（5秒超） | `http`クライアントの`timeout()` | `RouteApiException`→基本的に5章「状態遷移」の備考・7章#3の判定に従い`error`または`offline`表示 |
| 7 | Routes APIが5xx／想定外レスポンス形式（JSONパース失敗） | HTTPステータスコード／`FormatException`等 | `RouteApiException`として捕捉し`error`状態。詳細メッセージはログのみに留め、UIには一般化したメッセージを表示 |
| 8 | APIキー未設定・認証エラー（401/403） | HTTPステータスコード403等 | `RouteApiException`として`error`状態表示。原因はログにのみ出力（UIにAPIキー関連の内部情報は出さない） |
| 9 | 極端に長い／記号を含む入力文字列 | 特別なバリデーションは行わない | そのままAPIへ送信し、5の「該当駅なし」または7の「想定外レスポンス」として扱う（過度な入力制限はUXコンセプトに反するため設けない） |
| 10 | 同名駅の誤マッチ（例: 「府中」が東京都・広島県に複数存在する等） | 検知不可（Routes APIが返した候補をそのまま採用するため、アプリ側では気づけない） | **既知の制約事項**として受け入れる。本設計では入力文字列に「駅」を付与し`address`として渡す方式のみを採用し、同名駅の曖昧さ解消（現在地に近い方を優先する等の追加ロジック）はMVPスコープでは行わない（9章の未決定事項2も参照） |
| 11 | オフライン時に過去の検索結果（キャッシュ）を閲覧したい | - | **本Issue（F-02）のスコープ外**。architecture.md 8.2の「オフライン時はキャッシュ済みルート概要（`lastRouteSummaryJson`）の閲覧のみ提供する」という全体方針は、F-04（検索履歴、本Issueではスコープ外）が担う責務である。F-02がオフライン時に提供するのは「新規検索不可のバナー表示（`OfflineBanner`）のみ」であり、キャッシュ閲覧機能自体はF-02の実装に含めない |

## 8. テスト観点（flutter-test-writerが参照する）

### ユニットテスト
- **`RouteRepositoryImpl`**
  - 正常系: モックHTTPクライアントが正しいレスポンスJSONを返した場合、期待通りの`Route`にマッピングされること（徒歩・電車混在、乗換複数回のケースを含む）
  - 異常系: `routes`が空配列のレスポンス→`null`を返すこと
  - 異常系: HTTPステータス4xx/5xxの場合→`RouteApiException`をthrowすること
  - 異常系: タイムアウト時→`RouteApiException`をthrowすること
  - リクエスト内容検証: 送信するJSONボディに`origin`（現在地緯度経度）・`destination.address`（入力駅名+「駅」）・`travelMode: TRANSIT`・`computeAlternativeRoutes: false`が正しく含まれること
- **`SearchRouteUseCase`**
  - 正常系: Repositoryが`Route`を返せばそのまま返却すること
  - 異常系: Repositoryが`null`を返した場合`RouteNotFoundException`をthrowすること
  - 異常系: Repositoryが例外をthrowした場合、そのまま（または`RouteApiException`として）伝播すること
- **`RouteSearchNotifier`（`routeSearchProvider`）**
  - 正常系: 検索成功時に`loading`→`success`へ遷移し、状態に`Route`が保持されること
  - 異常系: `RouteNotFoundException`発生時に`notFound`へ遷移すること
  - 異常系: `RouteApiException`発生時に`error`へ遷移すること
  - ガード系: オフライン時に`search()`を呼び出してもAPI呼び出しが発生せず、状態が`offline`のままであること
  - ガード系: `currentLocationPointProvider`が`null`（現在地未取得）の時に`search()`を呼び出してもAPI呼び出しが発生せず、`locationUnavailable`のままであること
  - ガード系: 入力が空文字の場合にAPI呼び出しが発生しないこと
  - ガード系: `loading`中に`search()`を再度呼び出しても、Repository・UseCaseの呼び出しが2重に発生しないこと（二重送信ガード）
  - **優先度判定**: オフラインかつ現在地未取得（`locationUnavailable`の条件も同時に満たす状況）の場合に、状態（またはUI表示用のフラグ）としては`offline`が優先されること。`locationUnavailable`側の案内表示は行われないこと
  - **検索中にオフラインへ遷移するケースの振り分け**:
    - `loading`中に`connectivityStatusProvider`が`offline`を通知した場合（APIからの応答を待たずに接続断が検知された場合）は`offline`状態へ遷移すること
    - `loading`中、`connectivityStatusProvider`は`online`のまま（接続断は検知されていない）で、Routes API呼び出しがタイムアウト／通信エラーとなった場合は`error`状態へ遷移すること（オンラインだがAPI失敗のケースと、接続断そのもののケースを区別できることを確認する）
- **`connectivityStatusProvider`**
  - `connectivity_plus`のストリームがオフラインを通知した場合に状態が`offline`になること、オンライン復帰時に`online`へ戻ること

### Widgetテスト
- `SearchScreen`: オフライン時に`OfflineBanner`が表示され、検索ボタンが非活性になること
- `SearchScreen`: 現在地未取得時に検索ボタンが非活性で案内文が表示されること
- `SearchScreen`: **オフラインかつ現在地未取得の場合に、`OfflineBanner`（オフライン表示）が優先して表示され、`locationUnavailable`用の案内文は表示されないこと**（優先度判定の確認）
- `SearchScreen`: 検索リクエスト中（`loading`）は入力欄・検索ボタンが非活性になること
- `SearchScreen`: 正常系で駅名を入力し検索ボタンを押すとローディング表示→成功時に`RouteResultCard`が表示されること
- `SearchScreen`: 該当駅なしの場合に画面上部にフラッシュメッセージ（「見つかりませんでした」等）が表示されること。結果表示エリアは検索結果カードを表示せず直前の表示のままであり、入力欄の値もクリアされていないこと
- `SearchScreen`: APIエラー時にエラーメッセージが表示されること
- `RouteResultCard`: 徒歩・電車混在のルートが総所要時間・乗換回数・区間リストとして正しく表示されること

## 9. 未決定事項・確認したい点

1. **駅名入力にオートコンプリート（候補サジェスト）を導入するか**: requirements.md・architecture.mdには駅名入力のUI詳細（オートコンプリートの要否）についての明記がない。オートコンプリートを実装する場合、別途Google Places API（Autocomplete）等の追加APIが必要になり、確定済みの外部連携（Routes APIのみ）の範囲を超える可能性がある。本設計では**MVPでは単純なテキスト入力＋送信ボタンのみとし、オートコンプリートは導入しない**方針で設計したが、この判断でよいか確認したい（該当駅なしの発生率が上がる可能性はあるが、7章の異常系で対応する）。
2. **`destination`の指定方法（住所文字列 vs Place ID）**: 本設計では入力文字列に「駅」を付与して`address`として渡す方式としたが、同名駅が複数存在する場合（例: 「府中」が東京都・広島県に存在等）に意図しない駅がヒットするリスクがある。現在地に近い方を優先させる等の追加ロジックが必要かは未確定（Routes APIの`address`指定は現在地からの距離を考慮した曖昧検索をある程度行う可能性があるが、公式な保証は未確認のため実装時に要検証）。なお、architecture.md 4章の`SearchHistoryEntity.destinationStationPlaceId`はPlace IDを保持し再検索を高速化する想定であり、本論点（address指定かPlace ID指定か）はF-04（検索履歴）の設計とも関連するため、F-04の詳細設計時にあわせて再検討したい。
3. **`connectivityStatusProvider`の配置Issue**: オフライン判定は全機能共通のインフラであるため、本来はF-01（起動時から必要）で先に作るべきという考え方もある。本設計ではF-02で新規作成する前提としたが、Issue #1の設計・実装状況によっては責務の所在を調整したい。
4. **F-04（検索履歴、本Issueではスコープ外）との連携ポイント**: F-04は「検索成功時の履歴保存」を行う想定だが、本Issue（F-02）では履歴保存の実装は行わない。
   連携方法としては、`routeSearchProvider`が`success`状態へ遷移したタイミングで、F-04側が`ref.listen`等を用いて成功結果（入力駅名・`Route`概要）を監視し、`HistoryRepository`へ保存する形を想定している。
   ただし具体的な連携方法（Notifier内で直接履歴保存まで行うか、F-04側で監視する完全に疎な設計にするか）はF-04の詳細設計時に確定する。

### 確定事項（参考: ユーザーとの対話で解消した論点）

- **F-01（Issue #1）のインターフェース**: `LocationRepository.getCurrentLocation() : Future<LocationResult>`、`currentLocationProvider`（`StateNotifierProvider<CurrentLocationNotifier, LocationState>`）、`currentLocationPointProvider`（`Provider<LocationPoint?>`）として確定済み（2章参照）。F-02は`currentLocationPointProvider`を検索起点の取得に利用する。
- **「該当駅なし」時のUX**: 画面上部にフラッシュメッセージ（一時的な通知）で「該当する駅が見つかりませんでした」を表示する方式に確定。結果表示エリアは`idle`同様のプレースホルダー表示を維持し、入力欄の値もクリアしない（3章・4.1章・7章参照）。
