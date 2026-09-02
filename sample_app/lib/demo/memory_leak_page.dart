import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 詳細画面 1 枚が抱えるダミーデータの大きさ（2MB）。
///
/// リークしたときに Memory のグラフが階段状に増えるよう、
/// 目で見て分かる大きさにしてある。端末のメモリが厳しいときは減らす。
const int kPayloadBytes = 2 * 1024 * 1024;

/// 「開いて閉じる」を自動で繰り返す回数。
const int kCycleCount = 10;

/// アプリ全体で 1 つだけ存在する通知役。
///
/// 実務でいうと「ログイン状態」「テーマ」「WebSocket の受信」など、
/// 画面より長生きするものにあたる。
///
/// ここに登録した購読を `cancel()` し忘れると、購読しているオブジェクトは
/// **アプリが終わるまで回収されない**。これが dispose 漏れの正体。
final StreamController<int> appEventBus = StreamController<int>.broadcast();

int _createdPayloads = 0;
int _collectedPayloads = 0;

/// 回収された [DetailPayload] を数えるための仕掛け。
///
/// コールバックは GC が走ったあとに呼ばれる。DevTools で
/// Heap Snapshot を撮ると GC が走るので、そのあとに数字が動く。
final Finalizer<int> _payloadFinalizer = Finalizer<int>((int _) {
  _collectedPayloads++;
});

/// 詳細画面が抱える 2MB のダミーデータ。
///
/// Memory ▸ Diff で探しやすいように、他とかぶらない名前にしてある。
class DetailPayload {
  DetailPayload._(this.id) : bytes = Uint8List(kPayloadBytes);

  /// 生成と同時に「作った数」を数え、回収されたら分かるようにする。
  factory DetailPayload.create(int id) {
    final DetailPayload payload = DetailPayload._(id);
    _createdPayloads++;
    _payloadFinalizer.attach(payload, id, detach: payload);
    return payload;
  }

  final int id;
  final Uint8List bytes;
}

/// 「閉じたのに減らない」を体験するデモ。
///
/// 詳細画面を開くたびに 2MB のデータが作られる。詳細画面は
/// [appEventBus] を購読していて、後片付け（`cancel()`）をしないと
/// グローバルな StreamController が詳細画面の State を掴んだままになり、
/// 2MB もろとも回収されなくなる。
class MemoryLeakPage extends StatefulWidget {
  const MemoryLeakPage({super.key});

  @override
  State<MemoryLeakPage> createState() => _MemoryLeakPageState();
}

class _MemoryLeakPageState extends State<MemoryLeakPage> {
  /// true = dispose で cancel する（改善版） / false = しない（問題のある版）
  bool _cleanUp = false;
  bool _busy = false;
  int _opened = 0;
  int _nextId = 0;

  Timer? _busTimer;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // 画面より長生きするストリームに、定期的に値を流す役。
    _busTimer = Timer.periodic(const Duration(milliseconds: 200), (Timer timer) {
      if (!appEventBus.isClosed) {
        appEventBus.add(timer.tick);
      }
    });
    // 回収された数は GC のタイミングで動くので、定期的に表示を更新する。
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // このページ自身は、きちんと後片付けする。
    _busTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _openOnce() async {
    final NavigatorState navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            _DetailPage(id: _nextId++, cleanUp: _cleanUp),
      ),
    );
    if (mounted) {
      setState(() => _opened++);
    }
  }

  /// 「開いて閉じる」を自動で [kCycleCount] 回繰り返す。
  ///
  /// 手でやってもよいが、回数を揃えたほうが前後比較しやすい。
  Future<void> _cycle() async {
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _busy = true);

    for (int i = 0; i < kCycleCount; i++) {
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                _DetailPage(id: _nextId++, cleanUp: _cleanUp),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) {
        return;
      }
      navigator.pop();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) {
        return;
      }
      setState(() => _opened++);
    }

    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        _cleanUp ? const Color(0xFF0E8A6A) : const Color(0xFFD93A2B);
    final int alive = _createdPayloads - _collectedPayloads;

    return Scaffold(
      appBar: AppBar(
        title: const Text('③ 閉じたのに減らない'),
        actions: <Widget>[
          Row(
            children: <Widget>[
              Text(_cleanUp ? 'cancel する' : 'cancel しない'),
              Switch(
                value: _cleanUp,
                onChanged: _busy
                    ? null
                    : (bool value) => setState(() => _cleanUp = value),
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
                  _cleanUp ? Icons.check_circle : Icons.error,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _cleanUp
                        ? 'dispose() で subscription.cancel() する → 閉じたぶんは回収される'
                        : 'dispose() で cancel し忘れている → 閉じても回収されない',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Counters(
                    opened: _opened,
                    created: _createdPayloads,
                    collected: _collectedPayloads,
                    alive: alive,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _busy ? null : _cycle,
                    icon: const Icon(Icons.repeat),
                    label: const Text('開いて閉じるを $kCycleCount 回'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openOnce,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('詳細画面を 1 回だけ開く'),
                  ),
                  const SizedBox(height: 28),
                  Text('計測の手順', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '1. DevTools ▸ Memory を開く\n'
                    '2. Snapshot を 1 枚撮る（撮ると GC も走る）\n'
                    '3. 上のボタンで $kCycleCount 回ぶん開いて閉じる\n'
                    '4. もう 1 枚 Snapshot を撮る\n'
                    '5. Diff タブで 2 枚を比べ、DetailPayload を探す',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'cancel しない版では DetailPayload が $kCycleCount 個ぶん'
                    '（約 ${kCycleCount * kPayloadBytes ~/ (1024 * 1024)}MB）'
                    '増えたまま戻りません。スイッチを入れて同じ回数やり直すと、'
                    '増えたぶんが回収されます。\n'
                    'いちど漏らしたぶんはアプリを再起動するまで残ります。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

class _Counters extends StatelessWidget {
  const _Counters({
    required this.opened,
    required this.created,
    required this.collected,
    required this.alive,
  });

  final int opened;
  final int created;
  final int collected;
  final int alive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int aliveMb = alive * kPayloadBytes ~/ (1024 * 1024);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _Metric(label: '開いて閉じた回数', value: '$opened')),
            Expanded(child: _Metric(label: '作った DetailPayload', value: '$created')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: _Metric(
                label: '回収された（GC 後に反映）',
                value: '$collected',
                color: const Color(0xFF0E8A6A),
              ),
            ),
            Expanded(
              child: _Metric(
                label: '残っている',
                value: '$alive（約 ${aliveMb}MB）',
                color: alive > 0 ? const Color(0xFFD93A2B) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '「残っている」は目安です。ほんとうの答えは DevTools ▸ Memory ▸ Diff にあります。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 開いて閉じるだけの詳細画面。
///
/// やっていることは 2 つだけ:
///   1. 2MB のデータ ([DetailPayload]) を抱える
///   2. 画面より長生きする [appEventBus] を購読する
///
/// 2 を `dispose()` で `cancel()` しないと、StreamController → 購読 →
/// コールバック → この State → 2MB、という鎖でつながったままになる。
class _DetailPage extends StatefulWidget {
  const _DetailPage({required this.id, required this.cleanUp});

  final int id;

  /// true なら dispose() で購読を止める（＝正しい実装）。
  final bool cleanUp;

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> {
  late final DetailPayload _payload;
  StreamSubscription<int>? _subscription;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _payload = DetailPayload.create(widget.id);

    // このコールバックは State を掴んでいる。
    // つまり appEventBus が、この State ごと _payload を掴むことになる。
    _subscription = appEventBus.stream.listen((int value) {
      if (mounted) {
        setState(() => _ticks = value);
      }
    });
  }

  @override
  void dispose() {
    if (widget.cleanUp) {
      _subscription?.cancel();
    }
    // ここで cancel しないと、画面を閉じても appEventBus が購読を持ち続ける。
    // Widget ツリーから消えることと、メモリから消えることは別。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('詳細 #${_payload.id}')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'この画面は ${kPayloadBytes ~/ (1024 * 1024)}MB のデータを抱えています',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'appEventBus からの受信: $_ticks 回',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Text(
                widget.cleanUp
                    ? 'dispose() で cancel します'
                    : 'dispose() で cancel しません',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: widget.cleanUp
                      ? const Color(0xFF0E8A6A)
                      : const Color(0xFFD93A2B),
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
