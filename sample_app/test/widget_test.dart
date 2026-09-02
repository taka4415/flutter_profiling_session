import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/demo/heavy_work_page.dart';
import 'package:sample_app/demo/janky_list_page.dart';
import 'package:sample_app/main.dart';

void main() {
  testWidgets('ホームに 2 つのデモへの導線が出る', (WidgetTester tester) async {
    await tester.pumpWidget(const ProfilingDemoApp());

    expect(find.text('スクロールのジャンク'), findsOneWidget);
    expect(find.text('操作が固まる'), findsOneWidget);
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
}
