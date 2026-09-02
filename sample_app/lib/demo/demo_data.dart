import 'dart:math';

/// プロファイリング デモ用のダミーデータ。
///
/// 乱数のシードを固定しているので、何度アプリを起動しても
/// まったく同じデータになる。計測の前後比較をするときに
/// 「データが違うから速くなった/遅くなった」を排除するための工夫。
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.plays,
    required this.hue,
  });

  final int id;
  final String title;
  final String artist;
  final int plays;

  /// 行ごとの背景グラデーションに使う色相 (0-360)。
  final double hue;
}

const List<String> _words = <String>[
  'Midnight',
  'Paper',
  'Velvet',
  'Neon',
  'Harbor',
  'Slow',
  'Amber',
  'Static',
  'Little',
  'Northern',
  'Glass',
  'Quiet',
];

const List<String> _nouns = <String>[
  'Signal',
  'Garden',
  'Machine',
  'Avenue',
  'Weather',
  'Lantern',
  'Circuit',
  'Parade',
  'Window',
  'Orbit',
  'Comet',
  'Tide',
];

const List<String> _artists = <String>[
  'Aoi Terminal',
  'The Frame Budget',
  'Raster Kids',
  'Isolate',
  'Sixty Hertz',
  'Layer Tree',
  'Repaint Boundary',
  'Vsync',
];

/// [count] 件のダミートラックを生成する。
List<Track> buildTracks(int count) {
  final Random random = Random(20260902);
  return List<Track>.generate(count, (int index) {
    final String title =
        '${_words[random.nextInt(_words.length)]} ${_nouns[random.nextInt(_nouns.length)]}';
    return Track(
      id: index,
      title: title,
      artist: _artists[random.nextInt(_artists.length)],
      plays: 120 + random.nextInt(98000),
      hue: (index * 7.3) % 360,
    );
  });
}
