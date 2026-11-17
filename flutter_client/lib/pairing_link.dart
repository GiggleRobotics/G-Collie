import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'api.dart';

/// Parses the already supported invitation format without submitting a pairing.
({String address, String code})? parsePairingLink(String text) {
  try {
    final uri = Uri.parse(text.trim());
    final values = Uri.splitQueryString(uri.fragment);
    final code = values['pair'];
    if (code == null || !RegExp(r'^\d{6}$').hasMatch(code)) return null;
    final address = serverUri(uri.replace(fragment: '').toString());
    return (address: '$address', code: code);
  } catch (_) {
    return null;
  }
}

/// Accepts invitations pasted into either existing field; invalid URLs preserve
/// both fields. Numeric entry remains the normal code-field behaviour.
class PairingLinkFormatter extends TextInputFormatter {
  final TextEditingController address;
  final TextEditingController code;
  final bool codeField;
  PairingLinkFormatter({
    required this.address,
    required this.code,
    this.codeField = false,
  });
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final parsed = parsePairingLink(newValue.text);
    if (parsed != null) {
      final other = codeField ? address : code;
      final otherText = codeField ? parsed.address : parsed.code;
      other.value = TextEditingValue(
        text: otherText,
        selection: TextSelection.collapsed(offset: otherText.length),
      );
      final text = codeField ? parsed.code : parsed.address;
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    if (newValue.text.contains('://') || newValue.text.contains('#pair')) {
      if (codeField || newValue.text.contains('#')) return oldValue;
      final uri = Uri.tryParse(newValue.text);
      if (uri != null && uri.host.isNotEmpty) {
        try {
          serverUri(newValue.text);
        } catch (_) {
          return oldValue;
        }
      }
    }
    if (codeField && !RegExp(r'^\d{0,6}$').hasMatch(newValue.text)) {
      return oldValue;
    }
    return newValue;
  }
}
