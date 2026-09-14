import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/features/settings/models/node_display.dart';
import 'package:mostro/features/settings/models/node_selector_rules.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// `Agregar nodo propio` (handoff 9b): the public key is the focused,
/// Manrope-set field — hex digits align so the key can be checked by eye —
/// the name is visibly secondary, and a warning says why the key must be
/// verified with the operator.
///
/// The key is shape-checked here (64-char hex or `npub1…`) to enable
/// `Agregar` and to paint the error when the field loses focus; the
/// authoritative parse — checksum, nsec rejection, duplicates — stays in
/// Rust and is surfaced through [localizedNodeError].
class AddCustomNodeDialog extends ConsumerStatefulWidget {
  const AddCustomNodeDialog({super.key});

  @override
  ConsumerState<AddCustomNodeDialog> createState() =>
      _AddCustomNodeDialogState();
}

class _AddCustomNodeDialogState extends ConsumerState<AddCustomNodeDialog> {
  final _pubkeyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pubkeyFocus = FocusNode();
  final _nameFocus = FocusNode();

  /// Error under the key field: the shape error after a blur, or the Rust
  /// marker after a failed submit. Cleared on the next edit.
  String? _errorText;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _pubkeyFocus.addListener(_onPubkeyFocus);
    _nameFocus.addListener(_rebuild);
    _pubkeyCtrl.addListener(_rebuild);
    // The key is the field the user came to fill.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pubkeyFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _pubkeyFocus.removeListener(_onPubkeyFocus);
    _pubkeyCtrl.dispose();
    _nameCtrl.dispose();
    _pubkeyFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _pubkeyValid => looksLikeNodePubkey(_pubkeyCtrl.text);

  void _onPubkeyFocus() {
    if (!mounted) return;
    final text = _pubkeyCtrl.text.trim();
    if (!_pubkeyFocus.hasFocus && text.isNotEmpty && !_pubkeyValid) {
      setState(() => _errorText = _shapeError(text));
    } else {
      setState(() {});
    }
  }

  String _shapeError(String text) {
    final l10n = AppLocalizations.of(context);
    return looksLikePrivateKey(text)
        ? l10n.privateKeyNotAllowed
        : l10n.nodeInvalidPubkeyShort;
  }

  Future<void> _submit() async {
    final input = _pubkeyCtrl.text.trim();
    if (!_pubkeyValid || _submitting) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await ref
          .read(mostroNodesProvider.notifier)
          .addCustomNode(
            input: input,
            name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
          );
      // The user may have barrier-dismissed the dialog during the add;
      // popping via the captured navigator would then close the sheet.
      if (mounted) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.nodeAddedSuccess)));
    } catch (e) {
      debugPrint('[AddCustomNodeDialog] addCustomNode failed: $e');
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorText = localizedNodeError(l10n, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final canSubmit = _pubkeyValid && !_submitting;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          color: book.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: book.textPrimary.withValues(alpha: 0.08)),
          boxShadow: pal.dialogShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.addCustomNode,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: book.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            _UnderlineField(
              controller: _pubkeyCtrl,
              focusNode: _pubkeyFocus,
              label: l10n.nodePubkeyFieldLabel,
              hint: l10n.nodePubkeyFieldHint,
              errorText: _errorText,
              primary: true,
              enabled: !_submitting,
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              onSubmitted: (_) => _nameFocus.requestFocus(),
            ).withAutomationId(AutomationIds.nodeCustomPubkey),
            const SizedBox(height: 14),
            _UnderlineField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              label: l10n.nodeNameOptionalLabel,
              hint: l10n.nodeNameFieldHint,
              primary: false,
              enabled: !_submitting,
              onSubmitted: (_) => _submit(),
            ).withAutomationId(AutomationIds.nodeCustomName),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: pal.warnBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: pal.warnBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 13,
                      color: pal.dotWarn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.nodeVerifyKeyWarning,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: pal.warnInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 10,
                  child: OutlinedButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: book.textBody,
                      side: BorderSide(color: pal.buttonBorder),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      l10n.cancel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ).withAutomationId(AutomationIds.nodeAddCustomCancel),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 13,
                  child: FilledButton(
                    onPressed: canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: book.lime,
                      foregroundColor: book.onLime,
                      disabledBackgroundColor: pal.ctaDisabledBg,
                      disabledForegroundColor: pal.ctaDisabledInk,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child:
                        _submitting
                            ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: book.onLime,
                              ),
                            )
                            : Text(
                              l10n.addButtonLabel,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ).withAutomationId(AutomationIds.nodeCustomConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Uppercase label over an underlined value. [primary] is the key field:
/// Manrope 15/500 with a lime label while focused; the name field is Outfit
/// 15/400 with a faint label either way.
class _UnderlineField extends StatelessWidget {
  const _UnderlineField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.primary,
    required this.enabled,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final bool primary;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final focused = focusNode.hasFocus;
    final hasError = errorText != null;
    final labelColor =
        hasError
            ? pal.danger
            : (primary && focused ? pal.fieldLabelFocus : pal.fieldLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: 10, letterSpacing: 0.6, color: labelColor),
        ),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: primary ? TextInputType.visiblePassword : null,
          textInputAction:
              primary ? TextInputAction.next : TextInputAction.done,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          cursorColor: pal.fieldUnderlineFocus,
          style: TextStyle(
            fontFamily: primary ? AppFonts.figures : AppFonts.ui,
            fontSize: 15,
            fontWeight: primary ? FontWeight.w500 : FontWeight.w400,
            color: book.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: pal.fieldLabel,
            ),
            contentPadding: const EdgeInsets.only(top: 6, bottom: 8),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: hasError ? pal.danger : pal.fieldUnderline,
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: hasError ? pal.danger : pal.fieldUnderlineFocus,
                width: 1.5,
              ),
            ),
            disabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: pal.fieldUnderline),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 11, color: pal.danger),
            ),
          ),
      ],
    );
  }
}

/// Open the add-own-node dialog over the selector sheet.
Future<void> showAddCustomNodeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: OrderBookPalette.of(context).scrim,
    builder: (_) => const AddCustomNodeDialog(),
  );
}
