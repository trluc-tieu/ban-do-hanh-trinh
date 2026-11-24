import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import '../providers/map_settings_provider.dart';
import '../services/goong_service.dart';
import '../services/openmap_service.dart';
import 'smart_tile_provider.dart';

/// Shared OpenMap.vn / NDAMaps vector style lifecycle and base tile layer builder
/// for both [GoongMapWidget] and [PlacePickerMapWidget].
mixin VectorMapStyleMixin<T extends StatefulWidget> on State<T> {
  vt.Style? vectorStyle;
  bool isLoadingVectorStyle = false;
  String? vectorError;
  String? _activeVectorConfigSig;
  int _vectorLoadEpoch = 0;

  @override
  void dispose() {
    _vectorLoadEpoch++;
    final toDispose = vectorStyle;
    vectorStyle = null;
    super.dispose();
    if (toDispose != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toDispose.dispose();
      });
    }
  }

  /// Synchronizes loaded vector style with current [MapSettingsProvider].
  void syncVectorStyle(MapSettingsProvider settings) {
    final isVector = GoongService.isVectorStyle(settings.mapStyle);
    final sig = isVector
        ? '${settings.mapStyle.name}|${settings.openmapDomain}|${settings.openmapApiKey}|${settings.openmapCustomTileUrl}'
        : null;

    if (sig == _activeVectorConfigSig) return;
    _activeVectorConfigSig = sig;
    final epoch = ++_vectorLoadEpoch;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _vectorLoadEpoch) return;
      if (!isVector) {
        final old = vectorStyle;
        if (old != null || vectorError != null || isLoadingVectorStyle) {
          setState(() {
            vectorStyle = null;
            vectorError = null;
            isLoadingVectorStyle = false;
          });
          if (old != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
          }
        }
        return;
      }
      _loadVectorStyle(settings, epoch);
    });
  }

  Future<void> _loadVectorStyle(MapSettingsProvider settings, int epoch) async {
    final old = vectorStyle;
    setState(() {
      vectorStyle = null;
      isLoadingVectorStyle = true;
      vectorError = null;
    });
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }

    try {
      OpenMapService().setDomain(settings.openmapDomain);
      OpenMapService().setApiKey(settings.openmapApiKey);
      OpenMapService().setCustomTileUrl(settings.openmapCustomTileUrl);

      final loaded = await OpenMapService().loadVectorStyle(
        styleId: GoongService.vectorStyleId(settings.mapStyle),
        customKey: settings.openmapApiKey,
      );

      if (!mounted || epoch != _vectorLoadEpoch) {
        loaded.dispose();
        return;
      }
      setState(() {
        vectorStyle = loaded;
        isLoadingVectorStyle = false;
        vectorError = null;
      });
    } catch (e) {
      if (!mounted || epoch != _vectorLoadEpoch) return;
      setState(() {
        isLoadingVectorStyle = false;
        vectorError = _formatVectorError(e);
      });
    }
  }

  String _formatVectorError(Object err) {
    final msg = err
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StyleReaderException: ', '');
    if (msg.contains('401') || msg.contains('403')) {
      return 'API Key OpenMap / NDAMaps không hợp lệ hoặc chưa có quyền Map Tiles ($msg).';
    }
    return 'Không tải được bản đồ Vector NDAMaps: $msg';
  }

  /// Builds base raster or vector tile layer widgets for [FlutterMap].
  List<Widget> buildBaseMapLayers(
    MapSettingsProvider settings, {
    required VoidCallback onRasterTileError,
  }) {
    if (GoongService.isVectorStyle(settings.mapStyle)) {
      if (vectorStyle == null) return const [];
      return [
        vt.VectorTileLayer(
          key: ValueKey('vt_${vectorStyle.hashCode}'),
          theme: vectorStyle!.theme,
          tileProviders: vectorStyle!.providers,
          rasterSources: vectorStyle!.rasterSources,
          sprites: vectorStyle!.sprites,
          glyphs: vectorStyle!.glyphs,
        ),
      ];
    }

    return [
      TileLayer(
        urlTemplate: settings.tileUrl,
        userAgentPackageName: 'trluc.top.ban_do_hanh_trinh',
        maxZoom: 19,
        tileProvider: SmartTileProvider(),
        errorTileCallback: (tile, error, stackTrace) => onRasterTileError(),
      ),
    ];
  }
}
