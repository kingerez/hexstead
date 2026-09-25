import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../audio/sound_store.dart';
import '../monetization/purchase_store.dart';
import 'chrome.dart';

const String appStoreUrl = 'https://apps.apple.com/app/id6812996489';
const String playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.kingerez.hexstead';

Future<void> showPaywall(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const PaywallDialog(),
    );

/// The one purchase surface. On platforms with a store it sells the unlock;
/// on the web (and desktop) it becomes the funnel card pointing at the
/// mobile stores, where the full game lives.
class PaywallDialog extends StatefulWidget {
  const PaywallDialog({super.key});

  @override
  State<PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends State<PaywallDialog> {
  final _store = PurchaseStore.instance;
  String? _restoreMessage;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (_store.isUnlocked) {
      if (!_popped) {
        _popped = true;
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: parchmentPanel(radius: 16),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 320),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The Full Homestead',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4A3826),
                ),
              ),
              const SizedBox(height: 16),
              _benefit(Icons.groups, 'Face 2 or 3 rivals at once'),
              _benefit(Icons.local_fire_department,
                  'Fair and Cruel bots - far bigger score bonuses'),
              _benefit(Icons.block, 'No more ads, ever'),
              const SizedBox(height: 20),
              if (_store.purchasesSupported)
                ..._purchaseButtons()
              else
                ..._storeLinks(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _purchaseButtons() => [
        FilledButton(
          onPressed: () {
            SoundStore.instance.playSfx(Sfx.uiTap);
            _store.buy();
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
          child: Text(
            _store.price == null ? 'Unlock' : 'Unlock - ${_store.price}',
            style: const TextStyle(fontSize: 17),
          ),
        ),
        if (_store.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _store.lastError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8B3A2E), fontSize: 13),
            ),
          ),
        TextButton(
          onPressed: () async {
            SoundStore.instance.playSfx(Sfx.uiTap);
            final restored = await _store.restore();
            if (!mounted || restored) return;
            setState(() =>
                _restoreMessage = 'No purchase found for this account');
          },
          // The app theme is dark; its pale green vanishes on parchment,
          // so this link wears the panel's own gold.
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF9A6B1F),
          ),
          child: const Text(
            'Restore purchase',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (_restoreMessage != null)
          Text(
            _restoreMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF7A6647), fontSize: 13),
          ),
      ];

  // Same parchment-vs-dark-theme clash as the restore link: the store
  // buttons dress in the panel's wood and gold instead of the theme green.
  static final ButtonStyle _storeLinkStyle = OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFF9A6B1F),
    side: const BorderSide(color: Color(0xFF8A6F4D)),
  );

  List<Widget> _storeLinks() => [
        const Text(
          'The full game lives on your phone - grab it and your '
          'homestead grows.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF3A2E20), fontSize: 14),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () => launchUrl(Uri.parse(appStoreUrl)),
          style: _storeLinkStyle,
          child: const Text('App Store'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => launchUrl(Uri.parse(playStoreUrl)),
          style: _storeLinkStyle,
          child: const Text('Google Play'),
        ),
      ];

  Widget _benefit(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF9A6B1F)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF3A2E20),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
