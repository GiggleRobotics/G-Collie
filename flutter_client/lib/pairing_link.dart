import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'api.dart';

typedef PairingInvite = ({String address, String code});

bool isManualPairingCode(String code) => RegExp(r'^\d{6}$').hasMatch(code);

/// Parses the server's invitation token and the legacy six-digit link.
PairingInvite? parsePairingLink(String text) {
  try {
    final uri = Uri.parse(text.trim());
    final values = Uri.splitQueryString(uri.fragment);
    final code = values['pair'];
    if (code == null ||
        !(isManualPairingCode(code) ||
            RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(code))) {
      return null;
    }
    final address = serverUri(uri.replace(fragment: '').toString());
    return (address: '$address', code: code);
  } catch (_) {
    return null;
  }
}

/// An invitation is kept only for this form and bound to the original origin.
class PairingLinkDraft {
  PairingInvite? _invite;
  bool get hasInvite => _invite != null;
  void clear() => _invite = null;

  String? codeFor(String address, String manual) {
    final invite = _invite;
    if (invite != null) {
      try {
        return serverUri(address).toString() == invite.address
            ? invite.code
            : null;
      } catch (_) {
        return null;
      }
    }
    final code = manual.trim();
    return isManualPairingCode(code) ? code : null;
  }
}

/// Accepts invitations pasted into either existing field; invalid URLs preserve
/// both fields. Numeric entry remains the normal code-field behaviour.
class PairingLinkFormatter extends TextInputFormatter {
  final TextEditingController address;
  final TextEditingController code;
  final bool codeField;
  final PairingLinkDraft? draft;
  final VoidCallback? onInviteChanged;
  PairingLinkFormatter({
    required this.address,
    required this.code,
    this.codeField = false,
    this.draft,
    this.onInviteChanged,
  });
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final parsed = parsePairingLink(newValue.text);
    if (parsed != null) {
      draft?._invite = parsed;
      final displayedCode = isManualPairingCode(parsed.code) ? parsed.code : '';
      final other = codeField ? address : code;
      final otherText = codeField ? parsed.address : displayedCode;
      other.value = TextEditingValue(
        text: otherText,
        selection: TextSelection.collapsed(offset: otherText.length),
      );
      final text = codeField ? displayedCode : parsed.address;
      onInviteChanged?.call();
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
    if (draft?.hasInvite == true && oldValue.text != newValue.text) {
      draft!.clear();
      if (!codeField) code.clear();
      onInviteChanged?.call();
    }
    return newValue;
  }
}
