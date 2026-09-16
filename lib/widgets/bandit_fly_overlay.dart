import 'package:flutter/material.dart';

/// The bandit's entrance: appears huge at the board's center, then shrinks
/// and glides onto the hex it was placed on.
class BanditFlyOverlay extends StatefulWidget {
  final Offset start;
  final Offset target;
  final double endSize;
  final VoidCallback onDone;

  const BanditFlyOverlay({
    super.key,
    required this.start,
    required this.target,
    required this.endSize,
    required this.onDone,
  });

  @override
  State<BanditFlyOverlay> createState() => _BanditFlyOverlayState();
}

class _BanditFlyOverlayState extends State<BanditFlyOverlay>
    with SingleTickerProviderStateMixin {
  // Fly, then rest briefly on the tile before the painted bandit takes over.
  static const _flyMs = 650;
  static const _restMs = 250;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _flyMs + _restMs),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const startSize = 110.0;
    const flyFraction = _flyMs / (_flyMs + _restMs);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOutCubic
            .transform((_controller.value / flyFraction).clamp(0.0, 1.0));
        final pos = Offset.lerp(widget.start, widget.target, t)!;
        final size = startSize + (widget.endSize - startSize) * t;
        return Positioned(
          left: pos.dx - size / 2,
          top: pos.dy - size / 2,
          child: IgnorePointer(
            child: Text('🦹', style: TextStyle(fontSize: size)),
          ),
        );
      },
    );
  }
}
