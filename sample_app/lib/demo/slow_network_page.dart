import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'local_catalog.dart';

/// 通信の待ち時間。0 にすると「モックして消す」実験になる。
const int kNetworkDelayMs = 800;

/// 返す JSON の件数。AOT でパースが約 80〜150ms（M 系 Mac）。
/// 速すぎて固まりが見えないときは増やす。
const int kJsonItemCount = 120000;

const List<int> kDelayChoicesMs = <int>[0, 800, 2000];

/// カタログ JSON を組み立てる。Isolate に渡せるようトップレベル。
String buildCatalogJson(int itemCount) {
  final StringBuffer buffer = StringBuffer('[');
  for (int i = 0; i < itemCount; i++) {
    if (i > 0) {
      buffer.write(',');
    }
    buffer.write('{"id":$i,"name":"item_$i","score":${i % 9973}}');
  }
  buffer.write(']');
  return buffer.toString();
}

/// 巨大な JSON をパースして件数を返す。
///
/// 実務でいうと「API が返ってきた直後に、UI スレッドで jsonDecode して
/// 全件を setState する」。通信中ではなく、返ってきたあとに固まる。
int parseCatalog(String body) {
  final List<dynamic> items = jsonDecode(body) as List<dynamic>;
  int total = 0;
  for (final dynamic raw in items) {
    total += (raw as Map<String, dynamic>)['score'] as int;
  }
  return items.isEmpty ? total : items.length;
}

enum _Phase { preparing, idle, waiting, parsing, done }

/// 「通信が遅い？」を切り分けるデモ。
///
/// 端末内の HTTP サーバーがわざと遅く応答する。待っているあいだは
/// フレームカウンタが回り続ける（＝ジャンクではない）。返ってきた直後の
/// [parseCatalog] を UI スレッドでやると、そこで初めて数字が止まる。
class SlowNetworkPage extends StatefulWidget {
  const SlowNetworkPage({
    super.key,
    this.delayMs = kNetworkDelayMs,
    this.itemCount = kJsonItemCount,
  });

  final int delayMs;
  final int itemCount;

  @override
  State<SlowNetworkPage> createState() => _SlowNetworkPageState();
}

class _SlowNetworkPageState extends State<SlowNetworkPage> {
  bool _useIsolate = false;
  _Phase _phase = _Phase.preparing;
  int _delayMs = 0;
  String? _error;
  int? _loadedCount;
  int? _networkMs;
  int? _parseMs;

  CatalogEndpoint? _endpoint;

  @override
  void initState() {
    super.initState();
    _delayMs = widget.delayMs;
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final int itemCount = widget.itemCount;
      final String body = await Isolate.run(() => buildCatalogJson(itemCount));
      final CatalogEndpoint endpoint = CatalogEndpoint(
        body: body,
        delayMs: _delayMs,
      );
      await endpoint.start();
      if (!mounted) {
        await endpoint.close();
        return;
      }
      _endpoint = endpoint;
      setState(() => _phase = _Phase.idle);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.idle;
        _error = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _endpoint?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final CatalogEndpoint? endpoint = _endpoint;
    if (endpoint == null) {
      return;
    }
    endpoint.delayMs = _delayMs;

    setState(() {
      _phase = _Phase.waiting;
      _error = null;
      _loadedCount = null;
      _networkMs = null;
      _parseMs = null;
    });

    try {
      final Stopwatch networkWatch = Stopwatch()..start();
      final developer.TimelineTask waitTask = developer.TimelineTask()
        ..start('http GET /catalog');
      final String body = await endpoint.fetch();
      waitTask.finish();
      networkWatch.stop();

      if (!mounted) {
        return;
      }

      // 「パース中」の表示を 1 フレーム描いてから、同期処理に入る。
      setState(() {
        _phase = _Phase.parsing;
        _networkMs = networkWatch.elapsedMilliseconds;
      });
      await Future<void>.delayed(const Duration(milliseconds: 32));

      final Stopwatch parseWatch = Stopwatch()..start();
      final int count;
      if (_useIsolate) {
        final developer.TimelineTask task = developer.TimelineTask()
          ..start('jsonDecode (Isolate.run)');
        count = await Isolate.run(() => parseCatalog(body));
        task.finish();
      } else {
        developer.Timeline.startSync('jsonDecode (main isolate)');
        count = parseCatalog(body);
        developer.Timeline.finishSync();
      }
      parseWatch.stop();

      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.done;
        _loadedCount = count;
        _parseMs = parseWatch.elapsedMilliseconds;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.idle;
        _error = error.toString();
      });
    }
  }

  bool get _busy =>
      _phase == _Phase.preparing ||
      _phase == _Phase.waiting ||
      _phase == _Phase.parsing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = _bannerColor();

    return Scaffold(
      appBar: AppBar(
        title: const Text('④ 通信が遅い？'),
        actions: <Widget>[
          Row(
            children: <Widget>[
              Text(_useIsolate ? 'Isolate.run' : 'UI でパース'),
              Switch(
                value: _useIsolate,
                onChanged: _busy
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
                Icon(_bannerIcon(), size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _bannerText(),
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
                  const SizedBox(height: 28),
                  Text('通信の遅延', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final int ms in kDelayChoicesMs)
                        ChoiceChip(
                          label: Text(ms == 0 ? '0 ms（消す）' : '$ms ms'),
                          selected: _delayMs == ms,
                          onSelected: _busy
                              ? null
                              : (bool selected) {
                                  if (selected) {
                                    setState(() => _delayMs = ms);
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy || _endpoint == null ? null : _load,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('読み込む'),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(height: 72, child: _status(theme)),
                  if (_endpoint?.uri != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${_endpoint!.uri}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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

  Color _bannerColor() {
    if (_phase == _Phase.waiting) {
      return const Color(0xFF2F6FED);
    }
    return _useIsolate ? const Color(0xFF0E8A6A) : const Color(0xFFD93A2B);
  }

  IconData _bannerIcon() {
    if (_phase == _Phase.waiting) {
      return Icons.hourglass_top;
    }
    return _useIsolate ? Icons.check_circle : Icons.error;
  }

  String _bannerText() {
    if (_phase == _Phase.waiting) {
      return '通信中。Overlay は緑のまま、上の数字は回り続けるはずです';
    }
    if (_useIsolate) {
      return '返ってきたあとの jsonDecode を Isolate.run() へ → 数字は止まらない';
    }
    return '返ってきた直後に jsonDecode を UI スレッドで実行 → 「API が遅い」に見える';
  }

  Widget _status(ThemeData theme) {
    if (_error != null) {
      return Text(
        _error!,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.error),
      );
    }
    switch (_phase) {
      case _Phase.preparing:
        return Text('カタログを用意しています…', style: theme.textTheme.bodyMedium);
      case _Phase.idle:
        return Text(
          'ボタンを押して、上の数字を見ていてください',
          style: theme.textTheme.bodyMedium,
        );
      case _Phase.waiting:
        return Text('通信中…', style: theme.textTheme.titleMedium);
      case _Phase.parsing:
        return Text('パース中…', style: theme.textTheme.titleMedium);
      case _Phase.done:
        return Text(
          '通信 ${_networkMs} ms  /  パース ${_parseMs} ms  /  ${_loadedCount} 件',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        );
    }
  }
}

/// 毎フレーム 1 ずつ増えるカウンタ。
///
/// 通信の待ちでは回り続け、UI スレッドが止まった瞬間だけ止まる。
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
