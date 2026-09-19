import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Central sprite registry with per-asset fallback: any PNG present under
/// assets/images/ is used, anything missing keeps its placeholder. Load once
/// at startup; widgets and painters query synchronously afterwards.
class ArtStore {
  static final ArtStore instance = ArtStore._();

  ArtStore._();

  final Set<String> _available = {};
  final Map<String, ui.Image> _decoded = {};

  static const _tilePaths = {
    TerrainType.forest: 'assets/images/tiles/tile_forest.png',
    TerrainType.field: 'assets/images/tiles/tile_field.png',
    TerrainType.hill: 'assets/images/tiles/tile_hill.png',
    TerrainType.mountain: 'assets/images/tiles/tile_mountain.png',
    TerrainType.desert: 'assets/images/tiles/tile_desert.png',
  };

  static const banditPath = 'assets/images/bandit.png';

  bool _loaded = false;

  /// Discovers which art files were bundled and pre-decodes the ones the
  /// board painter draws directly.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _available.addAll(manifest
          .listAssets()
          .where((a) => a.startsWith('assets/images/')));
    } catch (_) {
      return; // no assets bundled yet - placeholders everywhere
    }
    for (final path in [..._tilePaths.values, banditPath]) {
      if (_available.contains(path)) {
        final data = await rootBundle.load(path);
        final codec =
            await ui.instantiateImageCodec(data.buffer.asUint8List());
        _decoded[path] = (await codec.getNextFrame()).image;
      }
    }
  }

  bool has(String path) => _available.contains(path);

  /// ImageProvider for a bundled asset, or null when it is not present -
  /// lets a BoxDecoration take the art without a widget in between.
  ImageProvider? provider(String path) =>
      has(path) ? AssetImage(path) : null;

  /// Decoded tile sprite for the painter, or null to use the placeholder.
  ui.Image? tileImage(TerrainType terrain) => _decoded[_tilePaths[terrain]];

  ui.Image? get banditImage => _decoded[banditPath];

  /// An Image widget that falls back to [placeholder] (usually an emoji
  /// Text) when the asset is not bundled.
  Widget image(String path,
      {required Widget placeholder, double? width, double? height, BoxFit? fit}) {
    if (!has(path)) return placeholder;
    return Image.asset(path, width: width, height: height, fit: fit);
  }
}
