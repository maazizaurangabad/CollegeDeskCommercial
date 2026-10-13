import 'package:flutter/material.dart';

/// Text input with the app's standard look.
class SdTextField extends StatelessWidget {
  const SdTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.errorText,
    this.onChanged,
    this.keyboardType,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
      ),
    );
  }
}
