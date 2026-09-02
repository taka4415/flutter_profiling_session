# sample_app — Flutter Profiling セッション用デモ

`slides/index.html`（セッション資料）とセットで使う、**わざと出来の悪いアプリ**です。
どのデモも右上のスイッチひとつで「問題のある版」と「改善版」を切り替えられるので、
DevTools を開いたまま A/B して、数字が変わるところを見せられます。

| デモ | 見るもの | DevTools |
|---|---|---|
| スクロールのジャンク | Raster スレッド | Performance |

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

## 端末に合わせた調整

端末が速すぎてジャンクが出ない / 遅すぎて操作できないときは、
以下の定数を変えてから `flutter run --profile` し直してください。

| 定数 | 場所 | 意味 |
|---|---|---|
| `kTrackCount` | `lib/demo/janky_list_page.dart` | リストの件数（既定 500） |
| `kWorkIterations` | `lib/demo/janky_list_page.dart` | 1 行あたりの計算量（既定 6000 ＝ M 系 Mac で約 0.6ms／行） |

## 確認

```sh
flutter analyze
flutter test
```
