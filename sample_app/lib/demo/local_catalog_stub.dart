/// Web など `dart:io` が無いときの代替。
///
/// 本物の HTTP は飛ばないので、DevTools の Network には何も出ない。
/// 待ち時間とパースの切り分け自体は、この遅延でも再現できる。
class CatalogEndpoint {
  CatalogEndpoint({required this.body, required this.delayMs});

  final String body;
  int delayMs;

  /// stub では HTTP を飛ばないので、常に null。
  Uri? uri;

  Future<void> start() async {}

  Future<String> fetch() async {
    if (delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
    return body;
  }

  Future<void> close() async {}
}
