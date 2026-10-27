import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth.dart';
import '../../auth/links.dart';
import '../../theme/app_theme.dart';

/// "Scan the QR code instead": the camera is asked for when this opens (on
/// the tap), never earlier. Reads `vpapp://signin/<token>` from the end user
/// portal's "Sign in the VoicePlatform app".
class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({super.key});

  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _onScan(Code code) async {
    if (_busy) return;
    final token = qrSignInToken(code.text ?? '');
    if (token == null) {
      setState(() => _message = "That isn't a VoicePlatform sign-in code.");
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authProvider.notifier).completeWithQr(token);
    } on SignInFailure catch (e) {
      if (mounted && e.message.isNotEmpty) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.callScreen(),
      child: Scaffold(
        backgroundColor: VpPalette.ink900,
        appBar: AppBar(
          backgroundColor: VpPalette.ink900,
          foregroundColor: VpPalette.grey100,
          leading: BackButton(onPressed: () => context.pop()),
          title: const Text('Scan the QR code'),
        ),
        body: Stack(
          children: [
            ReaderWidget(
              onScan: _onScan,
              codeFormat: Format.qrCode,
              showGallery: false,
              showToggleCamera: false,
              tryHarder: true,
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: VpPalette.ink900.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _busy ? 'Signing in' : _message ?? 'In the portal, open "Sign in the VoicePlatform app" and point the camera at the code.',
                    style: VpType.body.copyWith(color: VpPalette.grey100),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
