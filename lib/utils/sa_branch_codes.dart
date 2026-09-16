/// South African universal branch codes, for the Branch Code field's
/// auto-suggest.
///
/// A "universal" code is one the bank accepts for every one of its branches,
/// which is why a payer can be handed a single number rather than having to
/// know which branch an account was opened at. Suggesting them is the whole
/// point of the field: a mistyped branch code is one of the commonest causes
/// of a failed or misdirected EFT.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VERIFY THIS TABLE BEFORE RELEASE.
///
/// These are transcribed from public listings, not fetched from any
/// authoritative feed — the app never contacts a bank. A wrong code here
/// causes exactly the payment error this feature exists to prevent, so treat
/// every row as unverified until it has been checked against the bank's own
/// published universal branch code. Banks also merge and rebrand (Grobank →
/// Access Bank, Ubank, Postbank), which silently retires codes.
///
/// The suggestions are advisory only. Whatever the user types is what gets
/// saved and copied — nothing here overrides them.
/// ─────────────────────────────────────────────────────────────────────────
library;

/// One bank and the universal branch code it publishes.
class SaBranchCode {
  const SaBranchCode(this.bankName, this.code, {this.aliases = const []});

  final String bankName;
  final String code;

  /// Other names people type for the same bank, so searching "FNB" finds
  /// "First National Bank".
  final List<String> aliases;
}

const List<SaBranchCode> kSaBranchCodes = <SaBranchCode>[
  SaBranchCode('Absa Bank', '632005', aliases: ['absa']),
  SaBranchCode('African Bank', '430000'),
  SaBranchCode('Access Bank South Africa', '410105', aliases: ['grobank']),
  SaBranchCode('Bank Zero', '888000'),
  SaBranchCode('Bidvest Bank', '462005'),
  SaBranchCode('Capitec Bank', '470010', aliases: ['capitec']),
  SaBranchCode('Citibank', '350005'),
  SaBranchCode('Discovery Bank', '679000', aliases: ['discovery']),
  SaBranchCode('Finbond Mutual Bank', '589000'),
  SaBranchCode(
    'First National Bank',
    '250655',
    aliases: ['fnb', 'firstrand', 'rmb'],
  ),
  SaBranchCode('Grindrod Bank', '584000'),
  SaBranchCode('HBZ Bank', '570226'),
  SaBranchCode('Investec Bank', '580105', aliases: ['investec']),
  SaBranchCode('Ithala Bank', '757345'),
  SaBranchCode('Mercantile Bank', '450905'),
  SaBranchCode('Nedbank', '198765', aliases: ['nedbank']),
  SaBranchCode('Old Mutual Bank', '462005', aliases: ['old mutual']),
  SaBranchCode('Postbank', '460005', aliases: ['post office', 'sapo']),
  SaBranchCode('Sasfin Bank', '683000'),
  SaBranchCode('Standard Bank', '051001', aliases: ['standard', 'sbsa']),
  SaBranchCode('Standard Chartered Bank', '730020'),
  SaBranchCode('TymeBank', '678910', aliases: ['tyme']),
  SaBranchCode('Ubank', '431010'),
];

/// Suggestions for what the user has typed so far, matched against bank name,
/// alias, or the code itself — so both "cap" and "4700" find Capitec.
///
/// [bankName] is the Bank Name field's current text. When it names a bank, its
/// code is offered first even if the query is empty, which is the common case:
/// the user picks the bank, then taps into Branch Code expecting the right
/// number to be right there.
List<SaBranchCode> suggestBranchCodes(String query, {String bankName = ''}) {
  final q = query.trim().toLowerCase();
  final bank = bankName.trim().toLowerCase();

  bool matchesBank(SaBranchCode e) {
    if (bank.isEmpty) return false;
    final name = e.bankName.toLowerCase();
    if (name.contains(bank) || bank.contains(name)) return true;
    return e.aliases.any((a) => bank.contains(a));
  }

  bool matchesQuery(SaBranchCode e) {
    if (q.isEmpty) return true;
    return e.bankName.toLowerCase().contains(q) ||
        e.code.startsWith(q) ||
        e.aliases.any((a) => a.contains(q));
  }

  final matches = kSaBranchCodes.where(matchesQuery).toList();
  // Stable sort: entries for the bank already named float to the top, the
  // rest keep the alphabetical order of the table.
  matches.sort((a, b) {
    final aBank = matchesBank(a) ? 0 : 1;
    final bBank = matchesBank(b) ? 0 : 1;
    return aBank.compareTo(bBank);
  });
  return matches;
}
