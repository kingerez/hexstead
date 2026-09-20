import 'package:flutter/widgets.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../art/art_store.dart';

/// Resource and secret-task icons in one place: the PNG when it is bundled,
/// the emoji it replaces otherwise. Every screen pulls from here, so dropping
/// an asset in lights all of them up at once.

const _resourceEmoji = {
  Resource.wood: '🪵',
  Resource.grain: '🌾',
  Resource.brick: '🧱',
  Resource.stone: '🪨',
};

const _resourcePaths = {
  Resource.wood: 'assets/images/resources/wood.png',
  Resource.grain: 'assets/images/resources/grain.png',
  Resource.brick: 'assets/images/resources/brick.png',
  Resource.stone: 'assets/images/resources/stone.png',
};

const _taskEmoji = '🎯';
const _taskPath = 'assets/images/ui/icon_task.png';

/// A resource icon on its own, sized like the text it sits beside.
class ResourceIcon extends StatelessWidget {
  final Resource resource;
  final double size;

  const ResourceIcon(this.resource, {super.key, this.size = 15});

  @override
  Widget build(BuildContext context) =>
      _icon(_resourcePaths[resource]!, _resourceEmoji[resource]!, size);
}

/// The secret-task marker on its own.
class TaskIcon extends StatelessWidget {
  final double size;

  const TaskIcon({super.key, this.size = 15});

  @override
  Widget build(BuildContext context) => _icon(_taskPath, _taskEmoji, size);
}

Widget _icon(String path, String emoji, double size) =>
    ArtStore.instance.image(
      path,
      placeholder: Text(emoji, style: TextStyle(fontSize: size)),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

/// Inline resource icon for a Text.rich.
InlineSpan resourceSpan(Resource resource, double size) =>
    _span(_resourcePaths[resource]!, _resourceEmoji[resource]!, size);

/// Inline secret-task icon for a Text.rich.
InlineSpan taskSpan(double size) =>
    _span(_taskPath, _taskEmoji, size, _taskScale);

/// Inline art draws larger than the font size it sits in: a PNG confined
/// to the em box reads smaller than the emoji glyph it replaced.
const _inlineScale = 1.35;

/// The scroll is a wide, flat subject in its square frame, so it needs
/// extra room to match the visual weight of the resource icons.
const _taskScale = 2.1;

/// The fallback is a text span, not a placeholder widget: without art the
/// line must lay out - and read to a widget test - exactly as the plain
/// emoji string it replaced.
InlineSpan _span(String path, String emoji, double size,
    [double scale = _inlineScale]) {
  if (!ArtStore.instance.has(path)) return TextSpan(text: emoji);
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Image.asset(path,
        width: size * scale, height: size * scale, fit: BoxFit.contain),
  );
}

/// Price tag spans: "🪵1 🧱1", or "1 🪵" per entry with [countFirst].
List<InlineSpan> costSpans(
  Map<Resource, int> cost,
  double size, {
  bool countFirst = false,
  String separator = ' ',
}) {
  final spans = <InlineSpan>[];
  for (final entry in cost.entries) {
    if (spans.isNotEmpty) spans.add(TextSpan(text: separator));
    if (countFirst) {
      spans.add(TextSpan(text: '${entry.value} '));
      spans.add(resourceSpan(entry.key, size));
    } else {
      spans.add(resourceSpan(entry.key, size));
      spans.add(TextSpan(text: '${entry.value}'));
    }
  }
  return spans;
}
