import 'package:flutter_test/flutter_test.dart';
import 'package:metadata/utils/phone_number.dart';

void main() {
  group('normalizePhoneForMatching', () {
    test('strips formatting and country code down to the last 10 digits', () {
      expect(normalizePhoneForMatching('+1 (555) 123-4567'), '5551234567');
      expect(normalizePhoneForMatching('5551234567'), '5551234567');
      expect(normalizePhoneForMatching('555-123-4567'), '5551234567');
    });

    test('matches equivalent numbers in different formats', () {
      final a = normalizePhoneForMatching('+15551234567');
      final b = normalizePhoneForMatching('(555) 123-4567');
      expect(a, b);
    });

    test('returns all digits when shorter than 10', () {
      expect(normalizePhoneForMatching('12345'), '12345');
    });

    test('returns an empty string for input with no digits', () {
      expect(normalizePhoneForMatching('unknown'), '');
    });
  });

  group('toE164', () {
    test('strips formatting from an already-international number', () {
      expect(toE164('+1 (555) 123-4567', dialCode: '+92'), '+15551234567');
    });

    test('a leading + wins over the selected country', () {
      // The picker is a convenience, not an override: a number typed in full
      // is the number the user means.
      expect(toE164('+447700900123', dialCode: '+1'), '+447700900123');
    });

    test('prefixes the dial code onto a plain national number', () {
      expect(toE164('5551234567', dialCode: '+1'), '+15551234567');
      expect(toE164('7700 900123', dialCode: '+44'), '+447700900123');
    });

    test('drops the trunk prefix before the country code', () {
      // The bug this exists for: "+92" + "03001234567" texts +920300…, which
      // is not the user's number and never receives the code.
      expect(toE164('03001234567', dialCode: '+92'), '+923001234567');
      expect(toE164('07700 900123', dialCode: '+44'), '+447700900123');
    });

    test('treats 00 as the international prefix, not a trunk prefix', () {
      expect(toE164('0092 300 1234567', dialCode: '+1'), '+923001234567');
    });

    test('rejects input that cannot be a number', () {
      expect(toE164('', dialCode: '+1'), isNull);
      expect(toE164('   ', dialCode: '+1'), isNull);
      expect(toE164('not a number', dialCode: '+1'), isNull);
      expect(toE164('0', dialCode: '+92'), isNull);
    });

    test('rejects lengths E.164 does not allow', () {
      expect(toE164('12345', dialCode: '+1'), isNull);
      expect(toE164('1234567890123456', dialCode: '+1'), isNull);
    });
  });
}
