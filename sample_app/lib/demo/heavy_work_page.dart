import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 集計対象の件数。AOT で約 1〜1.5 秒（M 系 Mac）。
/// 速すぎて固まりが見えないときはチップを「長め」にする。
const int kRecordCount = 120000000;

const List<int> kRecordChoices = <int>[
  40000000,
  120000000,
  240000000,
];

/// 重い同期処理。
///
/// 実務でいうと「巨大な JSON を parse する」「数万件をその場で集計する」
/// にあたる。UI スレッドで動かすと、その間フレームが 1 枚も描けない。
///
/// 次の周回が前の合計に依存するので、コンパイラがループを消したり
/// ベクトル化したりしにくい。
///
/// [Isolate.run] に渡せるよう、トップレベル関数にしてある。
int aggregate(int records) {
  double total = 1;
  for (int i = 0; i < records; i++) {
    total += sqrt((total + i) % 9973) * log((i % 997) + 2);
    if (total > 1e12) {
      total = total / 9973;
    }
  }
  return total.round() % 100000;
}

/// Isolate の起動コストを先に払うための空処理。
///
/// State の中で `() => 0` を作ると this が混ざるので、トップレベルにする。
int isolateWarmup() => 0;

/// [aggregate] を別 isolate で走らせる。
///
/// `Isolate.run(() => aggregate(records))` を State のメソッド内で書くと、
/// クロージャのコンテキストに this（ウィジェットツリー）が入り、
/// 「object is unsendable」で落ちる。トップレベルなら件数だけが送られる。
Future<int> aggregateOffUi(int records) {
  return Isolate.run(() => aggregate(records));
}

/// 重い同期処理で UI スレッドが止まるところを見せるデモ。
///
/// 画面の中でアニメーションを回しっぱなしにしてあるので、
/// UI スレッドがブロックされた瞬間に「アニメーションが止まる」形で見える。
/// まばたきしても、いちばん長いフレーム間隔が残る。
class HeavyWorkPage extends StatefulWidget {
  const HeavyWorkPage({super.key, this.records = kRecordCount});

  final int records;

  @override
  State<HeavyWorkPage> createState() => _HeavyWorkPageState();
}

class _HeavyWorkPageState extends State<HeavyWorkPage> {
  bool _useIsolate = false;
  bool _running = false;
  int _runId = 0;
  late int _records;
  int? _result;
  Duration? _elapsed;

  @override
  void initState() {
    super.initState();
    _records = widget.records;
    // 最初の Isolate.run は isolate の起動コストが乗る。
    // 先に空回ししておくと、ON のときの対比がきれいになる。
    unawaited(Isolate.run(isolateWarmup));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _runId++;
      _result = null;
      _elapsed = null;
    });

    // ボタンが押された見た目と、カウンタのリセットを 1 フレーム描いてから走らせる。
    await Future<void>.delayed(const Duration(milliseconds: 32));

    final int records = _records;

    final Stopwatch stopwatch = Stopwatch()..start();
    final int value;
    if (_useIsolate) {
      // 非同期の区間は TimelineTask で囲む（start と finish が別フレームになるため）。
      final developer.TimelineTask task = developer.TimelineTask()
        ..start('aggregate (Isolate.run)');
      value = await aggregateOffUi(records);
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
                        ? '重い処理を Isolate.run() に逃がす → 四角は回り続け、間隔は 16ms 前後のまま'
                        : '重い処理を UI スレッドで実行 → 四角が止まり、いちばん長い間隔が跳ねる',
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
                  _FrameCounter(key: ValueKey<int>(_runId)),
                  const SizedBox(height: 28),
                  Text('計算量', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final int records in kRecordChoices)
                        ChoiceChip(
                          label: Text(_choiceLabel(records)),
                          selected: _records == records,
                          onSelected: _running
                              ? null
                              : (bool selected) {
                                  if (selected) {
                                    setState(() => _records = records);
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _running ? null : _run,
                    icon: const Icon(Icons.play_arrow),
                    label: Text('${_formatCount(_records)} 件を集計する'),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: _elapsed == null
                        ? Text(
                            _running ? '計算中…' : 'ボタンを押して、上の四角を見ていてください',
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

String _choiceLabel(int records) {
  if (records <= kRecordChoices.first) {
    return '短め';
  }
  if (records >= kRecordChoices.last) {
    return '長め';
  }
  return '標準';
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

/// 毎フレーム回る四角と、止まった証拠になる間隔表示。
///
/// UI スレッドが止まると四角も数字も止まる。再開したあと、
/// 「いちばん長い間隔」に止まった時間が残る。
class _FrameCounter extends StatefulWidget {
  const _FrameCounter({super.key});

  @override
  State<_FrameCounter> createState() => _FrameCounterState();
}

class _FrameCounterState extends State<_FrameCounter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _frames = 0;
  Duration _lastElapsed = Duration.zero;
  int _lastGapMs = 0;
  int _maxGapMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((Duration elapsed) {
      final int gapMs = elapsed.inMilliseconds - _lastElapsed.inMilliseconds;
      setState(() {
        _frames++;
        _lastElapsed = elapsed;
        _lastGapMs = gapMs;
        if (gapMs > _maxGapMs) {
          _maxGapMs = gapMs;
        }
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool froze = _maxGapMs >= 100;
    final Color gapColor = froze
        ? const Color(0xFFD93A2B)
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      children: <Widget>[
        Transform.rotate(
          angle: _frames * 0.18,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
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
        const SizedBox(height: 12),
        Text(
          '直前 ${_lastGapMs} ms  /  いちばん長い間隔 ${_maxGapMs} ms',
          style: theme.textTheme.titleSmall?.copyWith(
            color: gapColor,
            fontWeight: froze ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
