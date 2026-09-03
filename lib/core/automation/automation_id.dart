import 'package:flutter/material.dart';

/// Attaches a stable automation identifier to a control.
///
/// Prefer the [AutomationIdExtension.withAutomationId] extension over using
/// this widget directly: it applies at the end of the expression instead of
/// wrapping it, so adding an identifier does not re-indent the subtree.
///
/// The identifier is exposed as the Android accessibility `resource-id`
/// (Flutter `Semantics.identifier`), which black-box drivers locate without
/// depending on localized labels. By default the wrapped subtree is merged
/// into one semantics node, so the identifier, the visible label, the
/// enabled flag and the tap action travel together. Use `merge: false` for
/// composite rows that contain several independent controls; the identifier
/// then names the row container only.
class AutomationId extends StatelessWidget {
  const AutomationId(
    this.id, {
    super.key,
    required this.child,
    this.merge = true,
    this.label,
  });

  /// One of the `AutomationIds` constants or helpers.
  final String id;

  /// The control.
  final Widget child;

  /// Whether descendants are merged into a single semantics node.
  final bool merge;

  /// Optional explicit accessibility label, used for state readouts whose
  /// visible text is localized, truncated or not a plain `Text` — a harness
  /// asserts on this, never on the copy.
  ///
  /// A label on a merged subtree makes this node a *readout*: the descendants
  /// stop contributing semantics, so the label is exactly the value given and
  /// not that value with the visible copy appended. Composite rows that must
  /// keep their controls addressable pass `merge: false` instead.
  final String? label;

  @override
  Widget build(BuildContext context) {
    // `container: true` always introduces one node carrying the identifier.
    // In merge mode `MergeSemantics` folds every descendant into that node,
    // so label, flags and actions travel with the id (what the platform
    // accessibility bridge exposes). Otherwise descendants keep their own
    // nodes and only the explicit `label` describes the container.
    final isReadout = merge && label != null;
    final node = Semantics(
      identifier: id,
      label: label,
      container: true,
      explicitChildNodes: !merge,
      // A readout's value must be the label alone. Merging would otherwise
      // concatenate the visible copy onto it, and the copy is localized —
      // exactly what automation must not read.
      child: isReadout ? ExcludeSemantics(child: child) : child,
    );
    return merge ? MergeSemantics(child: node) : node;
  }
}

/// Attaches an automation identifier without wrapping the expression.
///
/// This is the preferred way to name a control:
///
/// ```dart
/// FilledButton(
///   onPressed: _submit,
///   child: Text(l10n.submitButton),
/// ).withAutomationId(AutomationIds.orderCreateSubmit)
/// ```
///
/// The semantics are identical to building an [AutomationId] around the
/// widget; the difference is that the identifier reads as a property of the
/// control rather than as an extra level of nesting.
extension AutomationIdExtension on Widget {
  /// Names this control with [id] for black-box UI automation.
  ///
  /// Pass `merge: false` for a row or card holding several independent
  /// controls, in which case [label] may carry the business state the
  /// harness asserts on. See `docs/automation-contract.md`.
  Widget withAutomationId(String id, {bool merge = true, String? label}) =>
      AutomationId(id, merge: merge, label: label, child: this);
}
