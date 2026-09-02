import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'demo_data.dart';

/// リストに並べる件数。多いほどジャンクが出やすい。
const int kTrackCount = 500;

/// 1行を build するたびに走らせる「わざと重い計算」の回数。
///
/// AOT で 1行あたり約 0.6ms（M 系 Mac 実測）。中位の実機ならその 3〜4 倍。
/// 端末が速すぎてジャンクが出ないときはここを増やし、
/// 逆に遅すぎて操作できないときは減らす。
const int kWorkIterations = 6000;

/// わざと重い同期計算。
///
/// 実務でいうと「build() の中で毎回やっている集計・整形・パース」の見立て。
/// 1回あたりのコストは小さくても、1フレームで何十回も呼ばれると
/// あっという間に 16.7ms の予算を食いつぶす。
int expensiveScore(Track track, int iterations) {
  double acc = track.plays.toDouble();
  for (int i = 1; i < iterations; i++) {
    acc = acc + sqrt((acc * i) % 9973) - log(i + 1);
  }
  return acc.round() % 1000;
}

/// スクロールがカクつく画面と、その改善版を **1画面のトグルで** 切り替えるデモ。
///
/// 画面遷移せずに前後比較できるので、DevTools の Flutter Frames チャートを
/// 開いたまま「赤いバーが消える」ところを見せられる。
class JankyListPage extends StatefulWidget {
  const JankyListPage({
    super.key,
    this.trackCount = kTrackCount,
    this.workIterations = kWorkIterations,
  });

  final int trackCount;
  final int workIterations;

  @override
  State<JankyListPage> createState() => _JankyListPageState();
}

class _JankyListPageState extends State<JankyListPage> {
  late final List<Track> _tracks;
  late final Map<int, int> _precomputedScores;
  late final Duration _precomputeCost;

  bool _optimized = false;

  @override
  void initState() {
    super.initState();
    _tracks = buildTracks(widget.trackCount);

    // 改善版はここで一度だけ計算しておく。
    // 「毎フレーム 60 回」と「起動時に 1 回」の差が、そのまま体感差になる。
    final Stopwatch stopwatch = Stopwatch()..start();
    _precomputedScores = <int, int>{
      for (final Track track in _tracks)
        track.id: expensiveScore(track, widget.workIterations),
    };
    stopwatch.stop();
    _precomputeCost = stopwatch.elapsed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('① スクロールのジャンク'),
        actions: <Widget>[
          Row(
            children: <Widget>[
              Text(_optimized ? '最適化 ON' : '最適化 OFF'),
              Switch(
                value: _optimized,
                onChanged: (bool value) => setState(() => _optimized = value),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _ModeBanner(
            optimized: _optimized,
            trackCount: _tracks.length,
            precomputeCost: _precomputeCost,
          ),
          Expanded(
            child: _optimized ? _buildFastList() : _buildSlowList(),
          ),
        ],
      ),
    );
  }

  /// 遅い版。やってはいけないことを 4 つ同時にやっている。
  Widget _buildSlowList() {
    // 1. ListView(children: ...) — 全件ぶんの Widget を毎 build で作る。
    return ListView(
      children: <Widget>[
        for (final Track track in _tracks)
          _SlowTrackTile(track: track, workIterations: widget.workIterations),
      ],
    );
  }

  /// 速い版。見た目はほぼ同じまま、コストだけ落とす。
  Widget _buildFastList() {
    // 1. ListView.builder — 画面に見えている行しか作らない。
    // 2. itemExtent — 行の高さが決まっているので、レイアウト計算を省ける。
    return ListView.builder(
      itemExtent: _kTileHeight,
      itemCount: _tracks.length,
      itemBuilder: (BuildContext context, int index) {
        final Track track = _tracks[index];
        return _FastTrackTile(
          track: track,
          score: _precomputedScores[track.id]!,
        );
      },
    );
  }
}

const double _kTileHeight = 96;

/// 遅い行。Raster スレッドを殺す描画を意図的に重ねている。
class _SlowTrackTile extends StatelessWidget {
  const _SlowTrackTile({required this.track, required this.workIterations});

  final Track track;
  final int workIterations;

  @override
  Widget build(BuildContext context) {
    // 3. build() の中で重い同期計算 — UI スレッドを削る。
    final int score = expensiveScore(track, workIterations);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: SizedBox(
        height: _kTileHeight - 8,
        // 4-a. Opacity — 子をいったんオフスクリーンに描いてから合成する。
        child: Opacity(
          opacity: 0.99,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              // 4-b. 影を 3 枚重ねる。
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 8,
                ),
              ],
            ),
            // 4-c. antiAliasWithSaveLayer — saveLayer() を強制的に呼ばせる。
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  DecoratedBox(decoration: _gradientFor(track)),
                  // 4-d. BackdropFilter — 背景をぼかす。Raster スレッドの本命の敵。
                  BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: const SizedBox.expand(),
                  ),
                  _TileContent(track: track, score: score),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 速い行。見た目はほぼ同じだが、レイヤーを 1 枚も増やさない。
class _FastTrackTile extends StatelessWidget {
  const _FastTrackTile({required this.track, required this.score});

  final Track track;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: DecoratedBox(
        // Opacity も ClipRRect も使わない。
        // 角丸は borderRadius で、半透明は色の alpha で直接指定する。
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: _gradientFor(track).gradient,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _TileContent(track: track, score: score),
      ),
    );
  }
}

BoxDecoration _gradientFor(Track track) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[
        HSLColor.fromAHSL(1, track.hue, 0.55, 0.42).toColor(),
        HSLColor.fromAHSL(1, (track.hue + 26) % 360, 0.60, 0.30).toColor(),
      ],
    ),
  );
}

class _TileContent extends StatelessWidget {
  const _TileContent({required this.track, required this.score});

  final Track track;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${track.artist} · ${track.plays} plays',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            score.toString().padLeft(3, '0'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// いま何が ON / OFF なのかを画面上に出しておく。
/// 観客が「トグルで何が変わったのか」を追えるようにするため。
class _ModeBanner extends StatelessWidget {
  const _ModeBanner({
    required this.optimized,
    required this.trackCount,
    required this.precomputeCost,
  });

  final bool optimized;
  final int trackCount;
  final Duration precomputeCost;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        optimized ? const Color(0xFF0E8A6A) : const Color(0xFFD93A2B);

    final List<String> lines = optimized
        ? const <String>[
            'ListView.builder + itemExtent（見えている行だけ build）',
            'スコアは initState で 1 回だけ計算（build から追い出した）',
            'Opacity / ClipRRect(saveLayer) を撤去（角丸は borderRadius）',
            'BackdropFilter を撤去・影は 1 枚',
          ]
        : const <String>[
            'ListView(children:) で全件ぶんの Widget を生成',
            'build() の中で毎回スコアを計算',
            'Opacity + ClipRRect(antiAliasWithSaveLayer)',
            'BackdropFilter(blur 8) + 影 3 枚',
          ];

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.10),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                optimized ? Icons.check_circle : Icons.error,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                optimized ? '改善版' : '問題のある版',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$trackCount 件 / 事前計算 ${precomputeCost.inMilliseconds}ms',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final String line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('・$line', style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
