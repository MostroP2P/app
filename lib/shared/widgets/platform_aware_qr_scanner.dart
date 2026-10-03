import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/input_source_action.dart';
import 'package:mostro/shared/widgets/paste_field.dart';

/// How [PlatformAwareQrScanner] takes its input on a platform.
enum QrInput {
  /// The device camera, through `mobile_scanner`.
  camera,

  /// A text field the user pastes or types into.
  paste,
}

/// Which [QrInput] a platform gets.
///
/// Callers pass `kIsWeb` and `defaultTargetPlatform`. `kIsWeb` is a parameter
/// rather than read here because it is a compile-time constant: a test could
/// otherwise never reach the web branch.
QrInput qrInputFor(bool isWeb, TargetPlatform platform) {
  // On web `platform` is the browser's OS: a phone browser reports android.
  if (isWeb) return QrInput.paste;
  return switch (platform) {
    TargetPlatform.android || TargetPlatform.iOS => QrInput.camera,
    // mobile_scanner implements Android, iOS, macOS and web only: on Linux
    // and Windows every channel call is a MissingPluginException and the
    // scanner renders nothing (#458). macOS has the plugin, but the sandboxed
    // app lacks `com.apple.security.device.camera` and
    // `NSCameraUsageDescription`, so it pastes until someone with a Mac
    // enables and tests the camera there.
    _ => QrInput.paste,
  };
}

/// Platform-aware QR scanner.
///
/// On **Android and iOS**: opens the device camera using `mobile_scanner`. If
/// the camera cannot start — no camera, or the permission refused — the paste
/// field below takes its place.
/// On **web and desktop**: shows a paste-from-clipboard text field. On web,
/// camera access requires HTTPS and a user gesture that differs across
/// browsers; on desktop, see [qrInputFor].
///
/// [onDetected] is called exactly once with the decoded string as soon as a
/// QR code is scanned or the user submits pasted content.
class PlatformAwareQrScanner extends StatefulWidget {
  const PlatformAwareQrScanner({
    super.key,
    required this.onDetected,
    this.hint = 'Paste or scan a QR code',
  });

  /// Called with the raw string value when a QR code is detected or submitted.
  final void Function(String value) onDetected;

  /// Placeholder text shown in the paste field.
  final String hint;

  @override
  State<PlatformAwareQrScanner> createState() => _PlatformAwareQrScannerState();
}

class _PlatformAwareQrScannerState extends State<PlatformAwareQrScanner> {
  final _controller = TextEditingController();
  String? _errorText;
  bool _hasEmitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emitOnce(String value) {
    if (_hasEmitted) return;
    _hasEmitted = true;
    widget.onDetected(value);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      setState(
        () => _errorText = AppLocalizations.of(context).clipboardEmptyError,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _errorText = null);
    _emitOnce(text);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = AppLocalizations.of(context).enterValueError);
      return;
    }
    _emitOnce(text);
  }

  Widget _pasteForm() {
    return _PasteFallback(
      controller: _controller,
      errorText: _errorText,
      hint: widget.hint,
      onChanged: (_) {
        if (_errorText != null) setState(() => _errorText = null);
      },
      onPaste: _pasteFromClipboard,
      onSubmit: _submit,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (qrInputFor(kIsWeb, defaultTargetPlatform) == QrInput.paste) {
      return _pasteForm();
    }
    return _CameraScanner(onDetected: _emitOnce, onError: _pasteForm);
  }
}

// ── Camera scanner (Android / iOS) ───────────────────────────────────────────

class _CameraScanner extends StatelessWidget {
  const _CameraScanner({required this.onDetected, required this.onError});

  /// Guarded by the parent's `_emitOnce`, so a code held in front of the
  /// camera for several frames is reported once.
  final void Function(String) onDetected;

  /// What replaces the preview when the camera cannot start.
  final Widget Function() onError;

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      // Without this, a refused permission or a device without a camera shows
      // mobile_scanner's black error box and nothing else to do.
      errorBuilder: (_, _) => onError(),
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
        if (raw != null && raw.isNotEmpty) onDetected(raw);
      },
    );
  }
}

// ── Paste fallback (web, desktop, camera unavailable) ────────────────────────

class _PasteFallback extends StatelessWidget {
  const _PasteFallback({
    required this.controller,
    required this.errorText,
    required this.hint,
    required this.onChanged,
    required this.onPaste,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? errorText;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.pasteQrCodeHeading,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: book.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PasteField(
            controller: controller,
            hint: hint,
            errorText: errorText,
            onChanged: onChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          InputSourceAction(
            icon: Icons.content_paste_outlined,
            label: l10n.pasteButtonLabel,
            onTap: onPaste,
          ),
          const SizedBox(height: 18),
          OrderPrimaryButton(
            label: l10n.submitButtonLabel,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}
