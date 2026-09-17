import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-game settings card: sound toggles (stored now, audio wired later)
/// and Home, which quits to the menu after confirmation. Progress is
/// autosaved, so quitting never loses a game.
class SettingsOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onQuitToMenu;

  const SettingsOverlay({
    super.key,
    required this.onClose,
    required this.onQuitToMenu,
  });

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  bool _music = true;
  bool _sounds = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _music = prefs.getBool('music_on') ?? true;
        _sounds = prefs.getBool('sounds_on') ?? true;
      });
    });
  }

  void _set(String key, bool value) {
    SharedPreferences.getInstance().then((p) => p.setBool(key, value));
  }

  Future<void> _confirmQuit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave the game?'),
        content: const Text(
            'Your progress is saved - you can continue from the menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok == true) widget.onQuitToMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: GestureDetector(
              onTap: () {},
              child: Material(
                color: const Color(0xFFF4EAD4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(
                      color: Color(0xFF8A6F4D), width: 2),
                ),
                child: Container(
                width: 300,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Settings',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3A2E20),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _toggle('Music', _music, (v) {
                      setState(() => _music = v);
                      _set('music_on', v);
                    }),
                    _toggle('Sounds', _sounds, (v) {
                      setState(() => _sounds = v);
                      _set('sounds_on', v);
                    }),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _confirmQuit,
                      icon: const Icon(Icons.home),
                      label: const Text('Home'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label,
          style: const TextStyle(
              color: Color(0xFF3A2E20), fontWeight: FontWeight.w600)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      activeThumbColor: const Color(0xFF9A6B1F),
    );
  }
}
