import 'package:flutter/material.dart';

import 'demo/heavy_work_page.dart';
import 'demo/janky_list_page.dart';
import 'demo/memory_leak_page.dart';
import 'demo/slow_network_page.dart';

void main() {
  runApp(const ProfilingDemoApp());
}

/// Flutter performance profiling セッション用のデモアプリ。
///
/// 必ず profile モードで起動すること:
///
/// ```
/// flutter run --profile -d <device>
/// ```
///
/// debug モードは JIT・assert・デバッグ用のチェックが入っているため、
/// 計測しても本番の性能とは別物になる。
class ProfilingDemoApp extends StatelessWidget {
  const ProfilingDemoApp({super.key});

  static const Color _seed = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Profiling Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      ),
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatelessWidget {
  const DemoHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profiling Demo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'どの画面も、右上のスイッチひとつで\n「問題のある版」と「改善版」を切り替えられます。',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '①② は Performance、③ は Memory、④ は Network と Performance を'
            '並べて見てください。',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _DemoCard(
            index: '01',
            title: 'スクロールのジャンク',
            subtitle: 'Raster スレッドが赤くなる例',
            bullets: const <String>[
              'ListView(children:) で 500 件を一括生成',
              'build() の中で毎回スコアを計算',
              'Opacity / ClipRRect(saveLayer) / BackdropFilter / 影 3 枚',
            ],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const JankyListPage(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _DemoCard(
            index: '02',
            title: '操作が固まる',
            subtitle: 'UI スレッドが完全にブロックされる例',
            bullets: const <String>[
              '重い同期処理を UI スレッドで実行',
              'アニメーションとフレームカウンタが止まるのが見える',
              'Isolate.run() に逃がすと止まらなくなる',
            ],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const HeavyWorkPage(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _DemoCard(
            index: '03',
            title: '閉じたのに減らない',
            subtitle: 'メモリが返ってこない例',
            bullets: const <String>[
              '詳細画面を開くたびに 2MB を確保',
              'グローバルな Stream を購読したまま cancel し忘れる',
              'Memory ▸ Diff で DetailPayload が増え続けるのが見える',
            ],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const MemoryLeakPage(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _DemoCard(
            index: '04',
            title: '通信が遅い？',
            subtitle: '待ちとカクつきを切り分ける例',
            bullets: const <String>[
              '端末内の HTTP サーバーがわざと遅く応答する',
              '待っているあいだフレームカウンタは回り続ける',
              '返った直後の jsonDecode で UI が止まる（スイッチで Isolate.run）',
            ],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const SlowNetworkPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.onTap,
  });

  final String index;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    index,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 14),
              for (final String bullet in bullets)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('・$bullet', style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
