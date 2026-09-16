/// Normalizes a phone number for loose matching between differently
/// formatted representations of the same number (e.g. "+1 (555) 123-4567"
/// vs "5551234567" vs "555-123-4567").
///
/// Strategy: strip everything but digits, then keep the last 10 digits.
/// This is a pragmatic compromise (no locale/country-code parsing, no new
/// dependency) — it can theoretically collide across countries that share
/// the same trailing 10 digits, and won't match numbers shorter than 10
/// digits against a longer stored variant, but it matches how most
/// caller-ID style apps behave in practice.
String normalizePhoneForMatching(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length <= 10) return digits;
  return digits.substring(digits.length - 10);
}

/// Turns what the user typed into the strict E.164 form Firebase phone auth
/// requires (`+` followed by digits only, nothing else), or null when it
/// cannot be one.
///
/// Firebase sends the SMS to exactly the string it is handed, so anything
/// this gets wrong is an OTP that never arrives — or worse, arrives at
/// somebody else's phone. The three ways a hand-typed number goes wrong:
///
///  * **Formatting.** `+1 (555) 123-4567` is not E.164; the spaces, parens
///    and dashes have to go.
///  * **The trunk prefix.** Most of the world writes its own numbers with a
///    leading `0` that exists only for domestic dialling — Pakistan's
///    `0300 1234567` is `+92 300 1234567`, not `+920300…`. Naively gluing the
///    dial code in front of it produces a number that is not the user's.
///  * **`00` as the international prefix.** `0092300…` already carries its
///    country code, so [dialCode] must not be added again.
///
/// A number the user typed with a leading `+` is taken as already
/// international and [dialCode] is ignored.
String? toE164(String raw, {required String dialCode}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  if (trimmed.startsWith('+')) return _validE164(digits);
  if (digits.startsWith('00')) return _validE164(digits.substring(2));

  final countryDigits = dialCode.replaceAll(RegExp(r'\D'), '');
  if (countryDigits.isEmpty) return null;

  // Drop the trunk prefix — no national number legitimately starts with 0.
  final national = digits.replaceFirst(RegExp(r'^0+'), '');
  if (national.isEmpty) return null;

  return _validE164('$countryDigits$national');
}

/// E.164 caps a number at 15 digits. The lower bound is deliberately loose
/// (the shortest national numbers in use are around 4 digits behind a 1-3
/// digit country code) — this rejects obvious typos, not unusual countries.
String? _validE164(String digits) {
  if (digits.length < 7 || digits.length > 15) return null;
  return '+$digits';
}
