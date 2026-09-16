import 'package:metadata/models/contact_model.dart';

/// How long a contact may go without any communication before the app flags
/// it for review.
///
/// Two years, expressed in days so it is a plain, testable [Duration]. Leap
/// days make the real anniversary drift by a day or two either way, which is
/// immaterial for a prompt whose own wording says "approximately".
const Duration kQuarantineAfter = Duration(days: 730);

/// The most recent evidence that this contact and the user were in touch.
///
/// A deliberate fallback chain, because [ContactModel.lastContactedAt] only
/// exists on contacts called since that field was added:
///
///  1. `lastContactedAt` — written by the outgoing and incoming call flows
///     only, so it means *communication* and nothing else.
///  2. `updatedAt` — the closest proxy on older contacts. It is bumped by
///     edits as well as calls, so an old contact whose notes were tidied last
///     month reads as recent. Erring that way is on purpose: quarantine
///     suggests deleting someone, and a missed prompt is cheaper than one
///     aimed at a contact the user is plainly still using.
///  3. `createdAt` — a contact that was saved and never touched again.
///
/// Null when the document carries none of the three, which happens for the
/// moment between a local write and the server resolving its timestamps.
DateTime? lastInteractionAt(ContactModel contact) =>
    contact.lastContactedAt ?? contact.updatedAt ?? contact.createdAt;

/// Whether this contact has been silent for [kQuarantineAfter] or longer.
///
/// False whenever that cannot be established rather than defaulting to true:
///
///  * a contact with no id is the stand-in synthesized from a call-log row
///    for an unsaved number — there is nothing to quarantine or delete;
///  * a contact with no timestamps at all (a write whose server timestamps
///    have not resolved yet) would otherwise flash "Quarantine" on a contact
///    saved seconds ago.
bool isQuarantined(ContactModel contact, {DateTime? now}) {
  if (contact.id.isEmpty) return false;
  final last = lastInteractionAt(contact);
  if (last == null) return false;
  return !(now ?? DateTime.now()).isBefore(last.add(kQuarantineAfter));
}

const List<String> _spelledYears = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
];

/// How long the silence has lasted, in the words the review prompt uses:
/// "approximately two years ago".
///
/// Rounded down to whole years and spelled out, because the prompt is read by
/// people the app is explicitly built for — including those who find dense
/// numeric text hard going. A precise date would be less useful here than
/// "about this long", and claiming precision the fallback chain above cannot
/// support would be worse than either.
String quarantineSilenceLabel(ContactModel contact, {DateTime? now}) {
  final last = lastInteractionAt(contact);
  if (last == null) return 'a long time ago';
  final years = (now ?? DateTime.now()).difference(last).inDays ~/ 365;
  if (years < 2) return 'a long time ago';
  if (years >= _spelledYears.length) return 'more than $years years ago';
  return 'approximately ${_spelledYears[years]} years ago';
}
