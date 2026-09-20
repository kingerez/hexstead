import 'package:flutter/material.dart';

import '../audio/sound_store.dart';
import 'chrome.dart';

/// The tutorial's guide strip: a parchment note pinned over the board that
/// says what to do next. It never takes a tap - the board and the chrome
/// underneath stay live - except for the Next/Finish button, which is the
/// only thing the player can press on the explanation-only beats.
///
/// Give it a key on the step id: a fresh State replays the entrance for
/// every new beat. The slide is one bounded controller, never a repeat(),
/// so pumpAndSettle still terminates.
class TutorialBanner extends StatefulWidget {
  final String text;

  /// Label for the trailing button; null hides it.
  final String? buttonLabel;
  final VoidCallback? onButton;

  const TutorialBanner({
    super.key,
    required this.text,
    this.buttonLabel,
    this.onButton,
  });

  @override
  State<TutorialBanner> createState() => _TutorialBannerState();
}

class _TutorialBannerState extends State<TutorialBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: eased,
      builder: (context, child) => Opacity(
        opacity: eased.value,
        child: Transform.translate(
          offset: Offset(0, -10 * (1 - eased.value)),
          child: child,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IgnorePointer(
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: parchmentPanel(radius: 12),
              child: Text(
                widget.text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A2E20),
                ),
              ),
            ),
          ),
          if (widget.buttonLabel != null) ...[
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () {
                SoundStore.instance.playSfx(Sfx.uiTap);
                widget.onButton?.call();
              },
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              ),
              child: Text(widget.buttonLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Amber halo around a piece of chrome the tutorial is pointing at. Static,
/// like the board buttons' own glow: a pulsing controller would keep widget
/// tests from ever settling.
class TutorialGlow extends StatelessWidget {
  final bool active;
  final double radius;
  final Widget child;

  const TutorialGlow({
    super.key,
    required this.active,
    required this.child,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.85),
            blurRadius: 14,
            spreadRadius: 2,
          ),
        ],
      ),
      child: child,
    );
  }
}
