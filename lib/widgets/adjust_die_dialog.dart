import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'dice_roll_overlay.dart';
import 'option_picker_dialog.dart';

/// Omen card UI: both dice side by side with up/down arrows. One nudge
/// total - picking an arrow previews it, picking another moves the nudge,
/// Done commits. Returns the chosen PlayCard, or null if dismissed.
///
/// Built as the *contents* of a parchment dialog, not a dialog of its own:
/// hand it to [showParchmentDialog] and it wears the same scrim, panel and
/// scale-in as the option picker and the confirmations.
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        parchmentTitle('Adjust a die'),
        const SizedBox(height: 12),
        const Text(
          'Nudge one die up or down by 1.',
          style: TextStyle(fontSize: 14, height: 1.3, color: parchmentInk),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _dieColumn(0),
            const SizedBox(width: 16),
            _dieColumn(1),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: parchmentWood),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.pop(context, _selected),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }

  /// One die on its own inset panel, the way the picker seats its rows,
  /// with the arrows that may move it above and below.
  Widget _dieColumn(int dieIndex) {
    final adjusted = _selected?.dieIndex == dieIndex;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: parchmentInset,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: adjusted ? parchmentAccent : parchmentWood,
          width: adjusted ? 2.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(dieIndex, 1, Icons.arrow_drop_up),
          MiniDie(_faceOf(dieIndex), size: 52),
          _arrow(dieIndex, -1, Icons.arrow_drop_down),
        ],
      ),
    );
  }

  Widget _arrow(int dieIndex, int delta, IconData icon) {
    // One nudge total: tapping another arrow simply moves it there.
    final enabled = _optionFor(dieIndex, delta) != null;
    return IconButton(
      onPressed: enabled ? () => _tapArrow(dieIndex, delta) : null,
      icon: Icon(icon, size: 38),
      color: parchmentAccent,
      disabledColor: parchmentWood.withValues(alpha: 0.35),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 34),
    );
  }
}
