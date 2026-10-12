# WKWebViewのテストが停止する問題の再現

> [!NOTE]
> FB25159342

iOS Simulatorで`WKWebView.evaluateJavaScript`を使うテストが、時々進まなくなる問題がありました。停止中のテストアプリのスタックを採取したところ、ScreenTimeのクライアントコードで同期XPCの応答を待つスレッドが確認できました。

この最小プロジェクトでは、ScreenTimeがこの停止に関与しているかを切り分けます。WebKitの`ScreenTimeEnabled`を有効・無効にし、同じ手順でページの読み込みとJavaScript実行を比較します。各WKWebViewの生成前にWKPreferencesの非公開APIでフラグを設定し、生成後の`configuration`から設定値を確認します。

各テストでは、1つのアプリプロセス内で同じ永続データストアを使い、次の処理を30回繰り返します。

1. WKWebViewを生成し、ウインドウに表示する。
2. HTTPSのURLを`baseURL`に指定し、外部リソースを使わないHTMLを読み込む。
3. `AsyncThrowingStream`で`didFinish`の通知を待つ。
4. `window.location.href`を評価する。
5. WKWebViewとウインドウを取り除く。

## 実行方法

環境情報とテスト結果を残すため、`Scripts/run.sh`で比較します。同じSimulatorで、有効・無効のケースを別々のアプリプロセスで順に実行します。

```sh
# 使用するXcodeのパスに合わせてください。
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl list devices available
./Scripts/run.sh <simulator-udid>
```

有効・無効それぞれの結果は`Results/`内の実行ごとのディレクトリに保存されます。保存先は実行時に表示されます。

- `xcodebuild.log`：実行環境と、各反復の進行ログ
- `result.xcresult`：テスト結果

## 観測結果

### 環境

- 測定日：2026年10月12日
- Mac：Apple M1 Pro、論理CPU 10個、メモリ32 GiB
- macOS：27.2（26B5101f）
- Xcode：27.1（27A9275）
- Simulator：iPhone 17、iOS 27.0（24A434）
- 実行順序：同じSimulatorで有効、無効の順に、別々のアプリプロセスで実行

### 比較結果

| `ScreenTimeEnabled` | 完了した読み込み | テスト本体の所要時間 | JavaScriptの評価 |
| --- | --- | --- | --- |
| `true` | 30/30 | 143.4秒 | 12回目の評価が返るまで124.5秒待った。 |
| `false` | 30/30 | 28.3秒 | 最も長い評価でも0.0165秒だった。 |

どちらのテストも最終的には成功しました。何回目で停止するかは、実行ごとに異なりました。

有効のケースの停止中にアプリのスタックを5秒間採取したところ、Swift Taskを実行していた10本のスレッドが同期XPCの応答を待っていました。スタックには以下が含まれていました。

- `ScreenTimeWebBrowserSettings.XPCClient`
- `DispatchQueue.sync`
- `BoardServices`
- `xpc_connection_send_message_with_reply_sync`

## 停止中のスタック採取

`[ScreenTimeRepro]`のログからアプリのPIDを確認し、進行が止まっている間にスタックを採取します。

```sh
mkdir -p Results
sample <app-pid> 10 -file Results/app.sample.txt
```

同じSimulatorのScreenTimeSettingsAgentも採取する場合は、ホスト側のPIDを取得して`sample`に渡します。

```sh
xcrun simctl spawn <simulator-udid> launchctl list |
  awk '$3 == "com.apple.ScreenTimeSettingsAgent" { print $1 }'
sample <agent-pid> 10 -file Results/settings-agent.sample.txt
```
