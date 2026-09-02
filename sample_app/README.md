# sample_app — Flutter Profiling セッション用デモ

`slides/index.html`（セッション資料）とセットで使う、**わざと出来の悪いアプリ**です。
どのデモも右上のスイッチひとつで「問題のある版」と「改善版」を切り替えられるので、
DevTools を開いたまま A/B して、数字が変わるところを見せられます。

| デモ | 見るもの | DevTools |
|---|---|---|
| ① スクロールのジャンク | Raster スレッド | Performance |
| ② 操作が固まる | UI スレッド | Performance |
| ③ 閉じたのに減らない | メモリ | Memory |
| ④ 通信が遅い？ | 待ち vs カクつき | Network + Performance |

## 動かし方

必ず **profile モード** で、できれば **実機** で起動します。

```sh
cd sample_app
flutter devices                 # 対象デバイスを確認
flutter run --profile -d <device-id>
```

起動すると `A Dart VM Service ... is available at:` と
`The Flutter DevTools debugger and profiler ... is available at:` の 2 行が出ます。
後者の URL をブラウザで開くと DevTools が立ち上がります。

> debug モード（`flutter run` そのまま）で測っても意味がありません。
> JIT・assert・デバッグ用チェックが入っているため、本番の性能とは別物です。

## デモ ①「スクロールのジャンク」

主に **Raster スレッド**が詰まる例です。

| | 最適化 OFF | 最適化 ON |
|---|---|---|
| リスト | `ListView(children:)` で 500 件を一括生成 | `ListView.builder` + `itemExtent` |
| スコア計算 | `build()` の中で毎回 | `initState` で 1 回だけ |
| 角丸 | `ClipRRect(clipBehavior: Clip.antiAliasWithSaveLayer)` | `BoxDecoration(borderRadius:)` |
| 半透明 | `Opacity` ウィジェット | 色の alpha を直接指定 |
| 効果 | `BackdropFilter(blur 8)` + 影 3 枚 | なし / 影 1 枚 |

**当日の流れ**

1. 最適化 OFF のままリストを勢いよくスクロールする
2. DevTools → Performance → Flutter Frames チャートに赤いバーが出る
3. 赤いバーをクリック → Frame Analysis タブでヒントを読む
4. （debug で）More debugging options の Render Clip layers / Opacity layers を OFF にして、犯人を絞る
   - このスイッチは **debug ビルド専用**です（サービス拡張が `assert` の中で登録されるため、profile では押せません）。切り分けだけ `--debug` で行い、時間の数字は profile で測り直します。
5. アプリ側のスイッチを ON にして、同じようにスクロールし直す
6. 赤が消えることを確認する

## デモ ②「操作が固まる」

**UI スレッド**が完全にブロックされる例です。画面中央のフレームカウンタと
インジケータが回りっぱなしなので、止まった瞬間が目で見えます。

- OFF: 重い集計を UI スレッドで実行 → カウンタが数百 ms 止まる
- ON: `Isolate.run()` に逃がす → カウンタは止まらない

`Timeline.startSync()` / `TimelineTask` で囲んであるので、
DevTools の Timeline Events に `aggregate (main isolate)` /
`aggregate (Isolate.run)` という名前の帯が出ます。

## デモ ③「閉じたのに減らない」

**メモリ**が返ってこない例です。時間ではなくメモリの話なので、見るのは
Performance ではなく **Memory** ビューです。

詳細画面を開くたびに 2MB の `DetailPayload` を確保し、同時に
アプリ全体で生きている `appEventBus`（グローバルな `StreamController`）を購読します。

- OFF: `dispose()` で `cancel()` しない → StreamController が購読 → コールバック →
  State → 2MB、という鎖でつながったままになり、**画面を閉じても回収されない**
- ON: `dispose()` で `cancel()` する → 閉じたぶんは回収される

**当日の流れ**

1. DevTools → Memory を開く
2. **Snapshot** を 1 枚撮る（撮ると GC も走る）
3. アプリの「開いて閉じるを 10 回」ボタンを押す
4. もう 1 枚 Snapshot を撮る
5. **Diff** タブで 2 枚を比べ、`DetailPayload` を探す
   - OFF なら 10 個（約 20MB）増えたまま。ON なら増えない
6. スイッチを ON にして、同じ回数やり直す

画面には「作った数 / 回収された数 / 残っている数」も出しています。
回収された数は GC が走ったあとに動くので、Snapshot を撮ると数字が追いつきます。
ただし目安なので、ほんとうの答えは Diff で見てください。

> いちど漏らしたぶんはアプリを再起動するまで残ります。
> 前後比較をするなら、スイッチを切り替えたあとに再起動するのがきれいです。

## デモ ④「通信が遅い？」

**待ち（通信）とカクつき（パース）** をごっちゃにしないための例です。
外の回線は使いません。端末の中で HTTP サーバーを立ち上げ、わざと遅く応答します。
DevTools の **Network** に `http://127.0.0.1:.../catalog` が出ます。

画面中央のフレームカウンタとインジケータが回りっぱなしなので、
「待っているあいだ」と「返ってきたあと」で挙動が違うのが目で見えます。

| | 最適化 OFF | 最適化 ON |
|---|---|---|
| 通信中 | カウンタは回り続ける（Overlay は緑） | 同じ |
| 返ってきた直後 | `jsonDecode` を UI スレッドで実行 → カウンタが止まる | `Isolate.run()` へ → 止まらない |

通信の遅延はチップで `0 ms` / `800 ms` / `2000 ms` に切り替えられます。
`0 ms` にしてもカクつくなら、通信は無関係です。

**当日の流れ**

1. DevTools の **Network** と **Performance** を並べて開く
2. 遅延 800 ms、スイッチ OFF で「読み込む」
3. 通信中はフレームカウンタが回り、Network に 1 本出る
4. 返った直後だけカウンタが止まり、Timeline に `jsonDecode (main isolate)` が出る
5. 遅延を `0 ms` にしてやり直す → まだ止まる（通信を消しても残る）
6. スイッチを ON にして同じ操作 → 止まらなくなる

結果行の「通信 ○○ ms / パース ○○ ms」が、切り分けの答えです。

## 端末に合わせた調整

端末が速すぎてジャンクが出ない / 遅すぎて操作できないときは、
以下の定数を変えてから `flutter run --profile` し直してください。

| 定数 | 場所 | 意味 |
|---|---|---|
| `kTrackCount` | `lib/demo/janky_list_page.dart` | リストの件数（既定 500） |
| `kWorkIterations` | `lib/demo/janky_list_page.dart` | 1 行あたりの計算量（既定 6000 ＝ M 系 Mac で約 0.6ms／行） |
| `kRecordCount` | `lib/demo/heavy_work_page.dart` | 集計件数（既定 40000000 ＝ M 系 Mac で約 270ms） |
| `kPayloadBytes` | `lib/demo/memory_leak_page.dart` | 詳細画面 1 枚が抱える大きさ（既定 2MB） |
| `kCycleCount` | `lib/demo/memory_leak_page.dart` | 自動で開いて閉じる回数（既定 10） |
| `kNetworkDelayMs` | `lib/demo/slow_network_page.dart` | 通信の待ち（既定 800ms。画面のチップでも変えられる） |
| `kJsonItemCount` | `lib/demo/slow_network_page.dart` | 返す JSON の件数（既定 120000。パースが速すぎるときは増やす） |

## 確認

```sh
flutter analyze
flutter test
```
