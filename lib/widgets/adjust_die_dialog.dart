import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'dice_roll_overlay.dart';

/// Omen card UI: both dice side by side with up/down arrows. One nudge
/// total - picking an arrow previews it, picking another moves the nudge,
/// Done commits. Returns the chosen PlayCard, or null if dismissed.
class AdjustDieDialog extends StatefulWidget {
  final int d1;
  final int d2;

  /// The legal omen plays right now.
  final List<PlayCard> options;

  const AdjustDieDialog({
    super.key,
    required this.d1,
    required this.d2,
    required this.options,
  });

  @override
  State<AdjustDieDialog> createState() => _AdjustDieDialogState();
}

class _AdjustDieDialogState extends State<AdjustDieDialog> {
  PlayCard? _selected;

  PlayCard? _optionFor(int dieIndex, int delta) {
    for (final o in widget.options) {
      if (o.dieIndex == dieIndex && o.delta == delta) return o;
    }
    return null;
  }

  int _faceOf(int dieIndex) {
    final base = dieIndex == 0 ? widget.d1 : widget.d2;
    if (_selected?.dieIndex == dieIndex) return base + _selected!.delta!;
    return base;
  }

  void _tapArrow(int dieIndex, int delta) {
    final option = _optionFor(dieIndex, delta);
    if (option == null) return;
    setState(() => _selected = _selected == option ? null : option);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adjust a die'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _dieColumn(0),
          const SizedBox(width: 28),
          _dieColumn(1),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _dieColumn(int dieIndex) {
    final adjusted = _selected?.dieIndex == dieIndex;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _arrow(dieIndex, 1, Icons.arrow_drop_up),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: adjusted ? Colors.amber : Colors.transparent,
              width: 3,
            ),
          ),
          child: MiniDie(_faceOf(dieIndex), size: 56),
        ),
        _arrow(dieIndex, -1, Icons.arrow_drop_down),
      ],
    );
  }

  Widget _arrow(int dieIndex, int delta, IconData icon) {
    // One nudge total: tapping another arrow simply moves it there.
    final enabled = _optionFor(dieIndex, delta) != null;
    return IconButton(
      onPressed: enabled ? () => _tapArrow(dieIndex, delta) : null,
      icon: Icon(icon, size: 40),
      color: enabled ? Colors.amber : Colors.white24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 36),
    );
  }
}
