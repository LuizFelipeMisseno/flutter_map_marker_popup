import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/extension_api.dart';
import 'package:flutter_map_marker_popup/src/options/popup_marker_layer_options.dart';
import 'package:flutter_map_marker_popup/src/popup_spec.dart';
import 'package:flutter_map_marker_popup/src/state/popup_state.dart';
import 'package:geodesy/geodesy.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'controller/popup_controller.dart';

@immutable
class MarkerLayer extends StatefulWidget {
  final PopupMarkerLayerOptions layerOptions;
  final MapCamera mapCamera;
  final MapController mapController;
  final PopupState popupState;
  final PopupController popupController;
  final GlobalKey? popupkey;

  const MarkerLayer({
    super.key,
    required this.layerOptions,
    required this.mapCamera,
    required this.mapController,
    required this.popupState,
    required this.popupController,
    this.popupkey,
  });

  @override
  State<MarkerLayer> createState() => _MarkerLayerState();
}

class _MarkerLayerState extends State<MarkerLayer> with SingleTickerProviderStateMixin {
  late AnimationController _centerMarkerController;
  void Function()? _animationListener;

  @override
  void initState() {
    super.initState();
    _centerMarkerController = AnimationController(
      vsync: this,
      duration: widget.layerOptions.markerCenterAnimation?.duration,
    );
  }

  @override
  void dispose() {
    _centerMarkerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = MapCamera.of(context);

    if (widget.layerOptions.selectedMarkerBuilder != null) {
      context.watch<PopupState>();
    }

    return MobileLayerTransformer(
      child: Stack(
        // ignore: avoid_types_on_closure_parameters
        children: (List<Marker> markers) sync* {
          for (final m in markers) {
            // Resolve real alignment
            final left = 0.5 * m.width * ((m.alignment ?? Alignment.center).x + 1);
            final top = 0.5 * m.height * ((m.alignment ?? Alignment.center).y + 1);
            final right = m.width - left;
            final bottom = m.height - top;

            // Perform projection
            final pxPoint = map.project(m.point);

            // Cull if out of bounds
            if (!map.pixelBounds.containsPartialBounds(
              Bounds(
                Point(pxPoint.x + left, pxPoint.y - bottom),
                Point(pxPoint.x - right, pxPoint.y + top),
              ),
            )) continue;

            // Apply map camera to marker position
            final pos = pxPoint.subtract(map.pixelOrigin);

            var markerChild = m.child;
            if (widget.layerOptions.selectedMarkerBuilder != null &&
                widget.popupState.isSelected(m)) {
              markerChild = widget.layerOptions.selectedMarkerBuilder!(context, m);
            }
            final markerWithGestureDetector = GestureDetector(
              onTap: () {
                if (!widget.popupState.selectedMarkers.contains(m)) {
                  _centerMarker(m);
                }

                widget.layerOptions.markerTapBehavior.apply(
                  PopupSpec.wrap(m),
                  widget.popupState,
                  widget.popupController,
                );
              },
              child: markerChild,
            );

            yield Positioned(
              key: m.key,
              width: m.width,
              height: m.height,
              left: pos.x - right,
              top: pos.y - bottom,
              child: (m.rotate == true)
                  ? Transform.rotate(
                      angle: -map.rotationRad,
                      alignment: (m.alignment ?? Alignment.center) * -1,
                      child: markerWithGestureDetector,
                    )
                  : markerWithGestureDetector,
            );
          }
        }(widget.layerOptions.markers)
            .toList(),
      ),
    );
  }

  void _centerMarker(Marker marker) {
    final markerLayerAnimation = widget.layerOptions.markerCenterAnimation;
    if (markerLayerAnimation == null) return;

    final fitPopupOnScreen = markerLayerAnimation.fitPopupOnScreen;

    double? topExtra;

    final popupHeight = widget.popupkey?.currentContext?.size?.height;

    if (fitPopupOnScreen && popupHeight != null) {
      switch (widget.layerOptions.popupDisplayOptions?.snap) {
        case PopupSnap.markerTop:
          final zoomLevel = widget.mapCamera.zoom;
          MediaQueryData mediaQueryData = MediaQuery.of(context);
          double screenWidth = mediaQueryData.size.width;
          double screenHeight = mediaQueryData.size.height;
          double screenAspectRatio = screenWidth / screenHeight;

          double mapResolution = zoomLevel * screenAspectRatio;

          final popupBottomLatLng = marker.point.add(
            y: marker.height / mapResolution,
          );
          final mapTopBound = widget.mapCamera.visibleBounds.north;

          CustomPoint<num> popupBottomPosition =
              const Epsg3857().latLngToPoint(popupBottomLatLng, zoomLevel);

          CustomPoint<num> mapTopPosition = const Epsg3857()
              .latLngToPoint(LatLng(mapTopBound, popupBottomLatLng.longitude), zoomLevel);

          final distanceToTop = mapTopPosition.y - popupBottomPosition.y;

          if (distanceToTop < popupHeight) {
            final differenceInPixels = popupHeight - distanceToTop;
            final latLngPixelsScale = differenceInPixels / mapResolution;
            topExtra = latLngPixelsScale;
          }
          break;
        default:
          break;
      }
    }

    final center = widget.mapCamera.center;
    final tween = LatLngTween(begin: center, end: marker.point.add(y: topExtra));

    Animation<double> animation = CurvedAnimation(
      parent: _centerMarkerController,
      curve: markerLayerAnimation.curve,
    );

    void listener() {
      widget.mapController.move(
        tween.evaluate(animation),
        widget.mapCamera.zoom,
      );
    }

    _centerMarkerController.removeListener(_animationListener ?? () {});
    _centerMarkerController.reset();
    _animationListener = listener;

    _centerMarkerController.addListener(listener);
    _centerMarkerController.forward().then((_) {
      _centerMarkerController
        ..removeListener(listener)
        ..reset();
      _animationListener = null;
    });
  }
}

extension LatLngUtils on LatLng {
  LatLng add({double? x, double? y}) {
    return LatLng(latitude + (y ?? 0), longitude + (x ?? 0));
  }
}
