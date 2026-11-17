import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/pairing_link.dart';

void main() {
  test(
    'invitation permits server-generated 32-char URL token and legacy code',
    () {
      expect(parsePairingLink('http://127.0.0.1:4310/#pair=123456'), (
        address: 'http://127.0.0.1:4310/',
        code: '123456',
      ));
      final token = base64Url.encode(
        List<int>.generate(24, (i) => (i * 71 + 252) % 256),
      );
      expect(token, hasLength(32));
      expect(parsePairingLink('https://qa:4310/?session=qa#pair=$token'), (
        address: 'https://qa:4310/',
        code: token,
      ));
      for (final invalid in [
        'http://host/#pair=123',
        'https://host/#pair=${'a' * 31}',
        'https://host/#pair=${'a' * 33}',
        'https://host/#pair=${'a' * 31}%2B',
        'http://host/path#pair=123456',
        'http://user:pass@host/#pair=123456',
        'bad#pair=123456',
      ]) {
        expect(parsePairingLink(invalid), isNull);
      }
    },
  );
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
  test(
    'in-memory invitation is bound to original origin and discarded on edit',
    () {
      final address = TextEditingController();
      final code = TextEditingController();
      final draft = PairingLinkDraft();
      final formatter = PairingLinkFormatter(
        address: address,
        code: code,
        draft: draft,
      );
      final token = base64Url.encode(List<int>.filled(24, 254));
      final ready = formatter.formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(text: 'http://first:4310/#pair=$token'),
      );
      expect(ready.text, 'http://first:4310/');
      expect(code.text, isEmpty);
      expect(draft.codeFor(ready.text, code.text), token);
      expect(draft.codeFor('http://first:4311/', '123456'), isNull);
      expect(draft.codeFor('https://first:4310/', '123456'), isNull);
      expect(draft.codeFor('http://other:4310/', '123456'), isNull);
      formatter.formatEditUpdate(
        ready,
        const TextEditingValue(text: 'http://other:4310/'),
      );
      expect(draft.hasInvite, isFalse);
      expect(draft.codeFor(ready.text, ''), isNull);
      expect(draft.codeFor('http://other:4310/', '123456'), '123456');
      address.dispose();
      code.dispose();
    },
  );
}
