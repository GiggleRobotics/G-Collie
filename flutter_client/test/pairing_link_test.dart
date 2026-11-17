import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/pairing_link.dart';

void main() {
  test('invitation parses only supported origin and six digit code', () {
    expect(parsePairingLink('http://127.0.0.1:4310/#pair=123456'), (
      address: 'http://127.0.0.1:4310/',
      code: '123456',
    ));
    for (final invalid in [
      'http://host/#pair=123',
      'http://host/path#pair=123456',
      'http://user:pass@host/#pair=123456',
      'bad#pair=123456',
    ]) {
      expect(parsePairingLink(invalid), isNull);
    }
  });
  test(
    'either field accepts invitation; invalid paste leaves other field unchanged',
    () {
      final address = TextEditingController(text: 'http://old/'),
          code = TextEditingController(text: '654321');
      for (final codeField in [false, true]) {
        final formatter = PairingLinkFormatter(
          address: address,
          code: code,
          codeField: codeField,
        );
        final old = TextEditingValue(
          text: codeField ? code.text : address.text,
        );
        final result = formatter.formatEditUpdate(
          old,
          const TextEditingValue(text: 'http://qa:4310/#pair=123456'),
        );
        expect(result.text, codeField ? '123456' : 'http://qa:4310/');
        expect(
          codeField ? address.text : code.text,
          codeField ? 'http://qa:4310/' : '123456',
        );
        final beforeAddress = address.text, beforeCode = code.text;
        expect(
          formatter.formatEditUpdate(
            old,
            const TextEditingValue(text: 'http://qa/path#pair=123456'),
          ),
          old,
        );
        expect(address.text, beforeAddress);
        expect(code.text, beforeCode);
      }
      address.dispose();
      code.dispose();
    },
  );
}
