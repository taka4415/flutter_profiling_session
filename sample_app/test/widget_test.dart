import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/demo/heavy_work_page.dart';
import 'package:sample_app/demo/janky_list_page.dart';
import 'package:sample_app/demo/memory_leak_page.dart';
import 'package:sample_app/demo/slow_network_page.dart';
import 'package:sample_app/main.dart';

void main() {
  testWidgets('ホームに 4 つのデモへの導線が出る', (WidgetTester tester) async {
    await tester.pumpWidget(const ProfilingDemoApp());

    expect(find.text('スクロールのジャンク'), findsOneWidget);
    expect(find.text('操作が固まる'), findsOneWidget);
    expect(find.text('閉じたのに減らない'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('通信が遅い？'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('通信が遅い？'), findsOneWidget);
  });

  testWidgets('リストデモの最適化トグルで表示が切り替わる', (WidgetTester tester) async {
    // テストは debug モードで走るので、件数と計算量を小さくして呼ぶ。
    await tester.pumpWidget(
      const MaterialApp(
        home: JankyListPage(trackCount: 12, workIterations: 50),
      ),
    );

    expect(find.text('問題のある版'), findsOneWidget);
    expect(find.text('改善版'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('改善版'), findsOneWidget);
    expect(find.text('問題のある版'), findsNothing);
  });

  testWidgets('重い処理デモは実行後に結果と所要時間を表示する', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HeavyWorkPage(records: 2000)),
    );

    expect(find.textContaining('ボタンを押して'), findsOneWidget);

    // このページはフレームカウンタとインジケータを回し続けているので、
    // pumpAndSettle は永久に落ち着かない。明示的に pump する。
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.textContaining('結果 '), findsOneWidget);
  });

  testWidgets('メモリデモ: cancel の有無で、閉じたあとに購読が残るかが変わる', (
    WidgetTester tester,
  ) async {
    // このページは Timer.periodic を回しているので pumpAndSettle は使えない。
    await tester.pumpWidget(const MaterialApp(home: MemoryLeakPage()));
    expect(appEventBus.hasListener, isFalse);

    Future<void> openAndClose() async {
      await tester.tap(find.text('詳細画面を 1 回だけ開く'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 詳細画面が購読を始めている
      expect(appEventBus.hasListener, isTrue);

      await tester.tap(find.text('閉じる'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 遷移が終わったフレームの次で、ルートが破棄されて dispose が走る。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 改善版（cancel する）: 閉じると購読も消える
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await openAndClose();
    expect(appEventBus.hasListener, isFalse);

    // 問題のある版（cancel しない）: 閉じても購読が残る = State ごとリーク
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await openAndClose();
    expect(appEventBus.hasListener, isTrue);
  });

  testWidgets('メモリデモ: 自動サイクルが最後まで走る', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MemoryLeakPage()));

    final Finder cycleButton =
        find.widgetWithText(FilledButton, '開いて閉じるを $kCycleCount 回');
    await tester.tap(cycleButton);
    await tester.pump();

    // 1 サイクルにつき 400ms×2。余裕を持って進める。
    for (int i = 0; i < kCycleCount * 2 + 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    // 走り切ってボタンが押せる状態に戻っている（＝途中で例外が出ていない）。
    final FilledButton button = tester.widget<FilledButton>(cycleButton);
    expect(button.onPressed, isNotNull);
    expect(find.text('$kCycleCount'), findsWidgets);
  });

  testWidgets('通信デモは待ちとパースの時間を分けて表示する', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SlowNetworkPage(delayMs: 20, itemCount: 40, useHttp: false),
      ),
    );
    await tester.pump();
    await tester.pump();

    final Finder loadButton = find.widgetWithText(FilledButton, '読み込む');
    expect(tester.widget<FilledButton>(loadButton).onPressed, isNotNull);

    await tester.tap(loadButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(find.textContaining('通信 '), findsOneWidget);
    expect(find.textContaining('パース '), findsOneWidget);
    expect(find.textContaining('40 件'), findsOneWidget);
  });

  testWidgets('通信デモの最適化トグルで表示が切り替わる', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SlowNetworkPage(delayMs: 0, itemCount: 8, useHttp: false),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('UI でパース'), findsOneWidget);
    expect(find.text('Isolate.run'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('Isolate.run'), findsOneWidget);
    expect(find.text('UI でパース'), findsNothing);
  });
}
