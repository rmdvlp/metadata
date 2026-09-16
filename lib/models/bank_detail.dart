import 'dart:convert';

/// How many sets of banking details one contact's Bank Chat can hold.
const int kMaxBankDetails = 4;

/// One person's banking details, as a payer would type them into their
/// banking app.
///
/// Deliberately all-`String`, including the numeric fields: an account number
/// is an identifier, not a quantity. Parsing "0012345678" as an int would
/// silently eat the leading zero and produce a number that pays nobody, and
/// some account numbers are longer than a 32-bit int anyway.
///
/// Nothing here is validated against a bank — the app never contacts one. It
/// stores what the user was given and makes it easy to copy without typos.
class BankDetail {
  const BankDetail({
    required this.id,
    this.bankName = '',
    this.accountType = '',
    this.accountNumber = '',
    this.branchCode = '',
    this.accountHolder = '',
    this.reference = '',
  });

  final String id;
  final String bankName;
  final String accountType;
  final String accountNumber;
  final String branchCode;
  final String accountHolder;
  final String reference;

  /// What to show as this entry's heading. The account holder is the most
  /// useful label — Bank Chat holds several people's details — with the bank
  /// as a fallback so an entry mid-edit is never a blank card.
  String get title {
    if (accountHolder.trim().isNotEmpty) return accountHolder.trim();
    if (bankName.trim().isNotEmpty) return bankName.trim();
    return 'Banking details';
  }

  bool get isEmpty =>
      bankName.trim().isEmpty &&
      accountType.trim().isEmpty &&
      accountNumber.trim().isEmpty &&
      branchCode.trim().isEmpty &&
      accountHolder.trim().isEmpty &&
      reference.trim().isEmpty;

  BankDetail copyWith({
    String? bankName,
    String? accountType,
    String? accountNumber,
    String? branchCode,
    String? accountHolder,
    String? reference,
  }) {
    return BankDetail(
      id: id,
      bankName: bankName ?? this.bankName,
      accountType: accountType ?? this.accountType,
      accountNumber: accountNumber ?? this.accountNumber,
      branchCode: branchCode ?? this.branchCode,
      accountHolder: accountHolder ?? this.accountHolder,
      reference: reference ?? this.reference,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'bankName': bankName,
    'accountType': accountType,
    'accountNumber': accountNumber,
    'branchCode': branchCode,
    'accountHolder': accountHolder,
    'reference': reference,
  };

  factory BankDetail.fromMap(Map<String, dynamic> map) => BankDetail(
    id: map['id'] as String? ?? '',
    bankName: map['bankName'] as String? ?? '',
    accountType: map['accountType'] as String? ?? '',
    accountNumber: map['accountNumber'] as String? ?? '',
    branchCode: map['branchCode'] as String? ?? '',
    accountHolder: map['accountHolder'] as String? ?? '',
    reference: map['reference'] as String? ?? '',
  );

  /// The whole entry as one block of text, for the "Copy All" action — the
  /// payer can paste it into a chat or notes app in one go.
  String toClipboardText() {
    final lines = <String>[
      if (bankName.trim().isNotEmpty) 'Bank: ${bankName.trim()}',
      if (accountHolder.trim().isNotEmpty)
        'Account holder: ${accountHolder.trim()}',
      if (accountType.trim().isNotEmpty) 'Account type: ${accountType.trim()}',
      if (accountNumber.trim().isNotEmpty)
        'Account number: ${accountNumber.trim()}',
      if (branchCode.trim().isNotEmpty) 'Branch code: ${branchCode.trim()}',
      if (reference.trim().isNotEmpty) 'Reference: ${reference.trim()}',
    ];
    return lines.join('\n');
  }

  static String encodeList(List<BankDetail> details) =>
      jsonEncode(details.map((d) => d.toMap()).toList());

  /// Tolerant on purpose: this reads a blob written by an older build of the
  /// app, and losing every entry because one is malformed would be worse than
  /// dropping that one.
  static List<BankDetail> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const <BankDetail>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <BankDetail>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(BankDetail.fromMap)
          .where((d) => d.id.isNotEmpty)
          .take(kMaxBankDetails)
          .toList();
    } catch (_) {
      return const <BankDetail>[];
    }
  }
}
