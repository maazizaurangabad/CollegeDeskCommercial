import 'package:flutter/material.dart';

import '../tokens/spacing.dart';
import 'sd_button.dart';

/// Short confirmation or information message at the bottom of the screen.
abstract final class SdToast {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Confirmation dialog. Destructive actions say exactly what will happen.
abstract final class SdDialog {
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          SdButton(
            label: cancelLabel,
            variant: SdButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SdButton(
            label: confirmLabel,
            variant: destructive ? SdButtonVariant.danger : SdButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Asks for one line of text, e.g. a name. Returns null when cancelled.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    required String label,
    required String confirmLabel,
    required String cancelLabel,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _PromptDialog(
        title: title,
        label: label,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        initial: initial,
      ),
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.initial,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String cancelLabel;
  final String initial;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        SdButton(label: widget.cancelLabel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(context).pop()),
        SdButton(label: widget.confirmLabel, onPressed: _submit),
      ],
    );
  }
}

/// Bottom sheet with a title, used for filters, pickers and overflow menus.
abstract final class SdSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, SdSpace.sm),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(child: builder(context)),
            const SizedBox(height: SdSpace.sm),
          ],
        ),
      ),
    );
  }
}
