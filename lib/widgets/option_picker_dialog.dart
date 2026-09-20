import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import 'chrome.dart';
import 'resource_icon.dart';

/// Ink and furniture shared by every parchment dialog in the game.
const parchmentInk = Color(0xFF3A2E20);
const parchmentWood = Color(0xFF8A6F4D);
const parchmentInset = Color(0xFFE7D9B8);

/// The accent parchment panels use for anything live: the setup chips, the
/// settings switch, and a dialog's own controls.
const parchmentAccent = Color(0xFF9A6B1F);

/// Enum names arrive lowercase; dialogs show them as words.
String capitalized(String name) =>
    name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

/// The shell every dialog here wears: a dark scrim, a parchment panel, and
/// the same scale-in the shop, trade and settings overlays use.
Future<T?> showParchmentDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext dialogContext) builder,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(20),
          decoration: parchmentPanel(radius: 18),
          child: builder(dialogContext),
        ),
      ),
    ),
  );
}

/// The heading every parchment dialog wears.
Widget parchmentTitle(String text) => Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: parchmentInk,
      ),
    );

/// One row of [showOptionPicker]: a leading mark (resource icon, player
/// swatch) beside its label.
class PickerOption<T> {
  final Widget leading;
  final String label;
  final T value;

  const PickerOption({
    required this.leading,
    required this.label,
    required this.value,
  });
}

/// The game's own "pick one" card: a parchment panel over a dark scrim,
/// scaling in the way the shop, trade and settings overlays do. Tapping
/// outside returns null, so a card that asks a question can always be
/// backed out of.
Future<T?> showOptionPicker<T>({
  required BuildContext context,
  required String title,
  required List<PickerOption<T>> options,
}) {
  return showParchmentDialog<T>(
    context: context,
    builder: (dialogContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        parchmentTitle(title),
        const SizedBox(height: 14),
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionRow(
              option: option,
              onTap: () => Navigator.pop(dialogContext, option.value),
            ),
          ),
      ],
    ),
  );
}

/// A yes-or-no card in the same language: a line of explanation, an optional
/// panel underneath (a price, say), then Cancel and the deed itself.
/// Returns true only when the player pressed [confirmLabel] - cancelling and
/// tapping outside both answer null.
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  Widget? body,
  String cancelLabel = 'Cancel',
}) {
  return showParchmentDialog<bool>(
    context: context,
    builder: (dialogContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        parchmentTitle(title),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(
              fontSize: 14, height: 1.3, color: parchmentInk),
        ),
        if (body != null) ...[
          const SizedBox(height: 14),
          body,
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(foregroundColor: parchmentWood),
              child: Text(cancelLabel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ],
    ),
  );
}

/// A price, rendered the way the picker renders its rows: each resource's
/// own art beside its name, with repeats collapsed into a count.
class ResourceCostRow extends StatelessWidget {
  final List<Resource> spend;

  const ResourceCostRow(this.spend, {super.key});

  @override
  Widget build(BuildContext context) {
    final counts = <Resource, int>{};
    for (final r in spend) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    final entries = counts.entries.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: parchmentInset,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: parchmentWood),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final (index, entry) in entries.indexed) ...[
            if (index > 0)
              const Text(
                '+',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: parchmentWood,
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResourceIcon(entry.key, size: 22),
                const SizedBox(width: 6),
                Text(
                  entry.value > 1
                      ? '${entry.value} ${capitalized(entry.key.name)}'
                      : capitalized(entry.key.name),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: parchmentInk,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final PickerOption<dynamic> option;
  final VoidCallback onTap;

  const _OptionRow({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: parchmentInset,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: parchmentWood),
          ),
          child: Row(
            children: [
              SizedBox(width: 26, child: Center(child: option.leading)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: parchmentInk,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round chip in a player's board color - the same mark their hexes and
/// score chip wear.
class PlayerSwatch extends StatelessWidget {
  final Color color;

  const PlayerSwatch(this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: parchmentInk, width: 1.5),
        ),
      );
}
