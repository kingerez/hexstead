import 'package:flutter/material.dart';

import '../art/art_store.dart';

/// Rounded translucent backing so floating chrome stays readable over the
/// board art.
BoxDecoration chromePill() => BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
    );

/// The parchment panel surface shared by the overlays and cards: cream
/// fill, wood border, rounded corners. Uses the parchment texture when it
/// is bundled and stays flat cream when it is not.
BoxDecoration parchmentPanel({
  double radius = 12,
  double borderWidth = 2,
  List<BoxShadow>? shadows,
}) {
  final texture = ArtStore.instance.provider('assets/images/ui/panel_bg.png');
  return BoxDecoration(
    color: const Color(0xFFF4EAD4),
    image: texture == null
        ? null
        : DecorationImage(image: texture, fit: BoxFit.cover),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: const Color(0xFF8A6F4D), width: borderWidth),
    boxShadow: shadows,
  );
}
