import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 集計対象の件数。約 270ms（M 系 Mac 実測）。中位の実機なら 1 秒前後。
/// 速すぎて固まりが分からないときは増やす。
const int kRecordCount = 40000000;

/// 重い同期処理。
///
/// 実務でいうと「巨大な JSON を parse する」「数万件をその場で集計する」
/// にあたる。UI スレッドで動かすと、その間フレームが 1 枚も描けない。
///
/// [Isolate.run] に渡せるよう、トップレベル関数にしてある。
int aggregate(int records) {
  double total = 0;
  for (int i = 0; i < records; i++) {
    total += sqrt(i % 9973) * log(i + 2);
  }
  return total.round() % 100000;
}

/// 重い同期処理で UI スレッドが止まるところを見せるデモ。
///
/// 画面の中でアニメーションを回しっぱなしにしてあるので、
/// UI スレッドがブロックされた瞬間に「アニメーションが止まる」形で見える。
class HeavyWorkPage extends StatefulWidget {
  const HeavyWorkPage({super.key, this.records = kRecordCount});

  final int records;

  @override
  State<HeavyWorkPage> createState() => _HeavyWorkPageState();
}

class _HeavyWorkPageState extends State<HeavyWorkPage> {
  bool _useIsolate = false;
  bool _running = false;
  int? _result;
  Duration? _elapsed;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
      _elapsed = null;
    });

    // ボタンが押された見た目を 1 フレームぶん描いてから走らせる。
    await Future<void>.delayed(const Duration(milliseconds: 32));

    // widget を直接キャプチャすると State ごと isolate に送ろうとして失敗するので、
    // 先にローカル変数へ取り出しておく。
    final int records = widget.records;

    final Stopwatch stopwatch = Stopwatch()..start();
    final int value;
    if (_useIsolate) {
      // 非同期の区間は TimelineTask で囲む（start と finish が別フレームになるため）。
      final developer.TimelineTask task = developer.TimelineTask()
        ..start('aggregate (Isolate.run)');
      value = await Isolate.run(() => aggregate(records));
      task.finish();
    } else {
      // 同期の区間は Timeline.startSync / finishSync で囲む。
      // DevTools の Timeline Events に、この名前で太い帯が出る。
      developer.Timeline.startSync('aggregate (main isolate)');
      value = aggregate(records);
      developer.Timeline.finishSync();
    }
    stopwatch.stop();

    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _result = value;
      _elapsed = stopwatch.elapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        _useIsolate ? const Color(0xFF0E8A6A) : const Color(0xFFD93A2B);

    return Scaffold(
      appBar: AppBar(
        title: const Text('② 操作が固まる'),
        actions: <Widget>[
          Row(
            children: <Widget>[
              Text(_useIsolate ? 'Isolate.run' : 'UI スレッド'),
              Switch(
                value: _useIsolate,
                onChanged: _running
                    ? null
                    : (bool value) => setState(() => _useIsolate = value),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: color.withValues(alpha: 0.10),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: <Widget>[
                Icon(
                  _useIsolate ? Icons.check_circle : Icons.error,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _useIsolate
                        ? '重い処理を Isolate.run() に逃がす → アニメーションは回り続ける'
                        : '重い処理を UI スレッドで実行 → その間フレームが 1 枚も描けない',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const _FrameCounter(),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: _running ? null : _run,
                    icon: const Icon(Icons.play_arrow),
                    label: Text('${_formatCount(widget.records)} 件を集計する'),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: _elapsed == null
                        ? Text(
                            _running ? '計算中…' : 'ボタンを押して、上の数字を見ていてください',
                            style: theme.textTheme.bodyMedium,
                          )
                        : Text(
                            '結果 $_result / ${_elapsed!.inMilliseconds} ms',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 3 桁ごとに区切って読みやすくする。
String _formatCount(int value) {
  final String digits = value.toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 毎フレーム 1 ずつ増えるカウンタ。
///
/// UI スレッドが止まると、この数字も止まる = フレームが落ちている証拠になる。
/// setState の範囲をこのウィジェットの中だけに閉じてあるのがポイント
/// （ページ全体を毎フレーム rebuild しないため）。
class _FrameCounter extends StatefulWidget {
  const _FrameCounter();

  @override
  State<_FrameCounter> createState() => _FrameCounterState();
}

class _FrameCounterState extends State<_FrameCounter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((Duration elapsed) {
      setState(() => _frames++);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(strokeWidth: 6),
        ),
        const SizedBox(height: 24),
        Text(
          _frames.toString().padLeft(6, '0'),
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const Text('描けたフレーム数'),
      ],
    );
  }
}
