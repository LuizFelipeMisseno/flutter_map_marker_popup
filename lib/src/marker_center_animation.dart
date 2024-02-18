import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

class MarkerCenterAnimation {
  final Duration duration;
  final Curve curve;
  final bool fitPopupOnScreen;
  final EdgeInsets? padding;

  const MarkerCenterAnimation({
    this.duration = const Duration(milliseconds: 500),
    this.curve = Curves.ease,
    this.fitPopupOnScreen = false,
    this.padding,
  });
}
