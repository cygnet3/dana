import 'package:danawallet/global_functions.dart';
import 'package:flutter/material.dart';

/// Inline error message for a failed frigate reachability probe (finding
/// t_3ba59c28): the cleaned first-line message via [exceptionToString] —
/// never the raw `AnyhowException(...)` wrapper that used to leak into the
/// transient snackbar.
String frigateProbeFailureMessage(Object e) =>
    'Frigate unreachable: ${exceptionToString(e)}';

/// URL dialog for the frigate backend save flow (D10, t_d3352d51 spec;
/// restores the UX lost to finding t_3ba59c28).
///
/// On OK the entered URL is handed to [validate] (parse -> probe ->
/// chain-consistency, supplied by the caller). While it runs the action
/// buttons are disabled; on failure the dialog STAYS OPEN and the error is
/// shown as a persistent inline [InputDecoration.errorText] on the URL
/// field — the text is preserved so the user can correct and retry without
/// retyping, and editing the field clears the stale error. On success the
/// dialog pops with the URL string; Cancel pops null, Reset pops true.
class FrigateUrlDialog extends StatefulWidget {
  final TextEditingController controller;
  final String titleText;
  final String labelText;
  final bool showReset;

  /// Returns null when the URL is accepted, or the inline error to display.
  final Future<String?> Function(String url) validate;

  const FrigateUrlDialog({
    super.key,
    required this.controller,
    required this.titleText,
    required this.labelText,
    required this.validate,
    this.showReset = true,
  });

  @override
  State<FrigateUrlDialog> createState() => _FrigateUrlDialogState();
}

class _FrigateUrlDialogState extends State<FrigateUrlDialog> {
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _checking = true;
    });
    final error = await widget.validate(widget.controller.text);
    if (!mounted) return;
    setState(() => _checking = false);
    if (error != null) {
      // Failure: stay open, surface the error inline on the field.
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titleText),
      content: TextField(
        controller: widget.controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: widget.labelText,
          errorText: _error,
          errorMaxLines: 4,
        ),
      ),
      actions: <Widget>[
        if (widget.showReset)
          TextButton(
            onPressed: _checking
                ? null
                : () {
                    Navigator.of(context).pop(true); // reset requested
                  },
            child: const Text('Reset to default'),
          ),
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _checking ? null : _submit,
          child: const Text('OK'),
        ),
      ],
    );
  }
}
