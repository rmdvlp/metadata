import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/bank_detail.dart';
import 'package:metadata/repositories/bank_chat_repository.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/sa_branch_codes.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/copyable_field.dart';

/// Bank Chat: up to [kMaxBankDetails] sets of banking details kept against one
/// contact, every field one tap from the clipboard.
///
/// The problem it solves is retyping. A payer reading an account number off a
/// screen and typing it into a banking app is the step where money goes to the
/// wrong place, and it is hardest for exactly the people most likely to be
/// paying this way — older users, users with poor eyesight, users who are not
/// confident with a phone keyboard. So nothing here is editable in place and
/// nothing is validated against a bank: the app holds what the user was given
/// and makes copying it exact.
///
/// Storage is device-local. See [BankChatRepository].
class BankChatScreen extends ConsumerWidget {
  const BankChatScreen({
    super.key,
    required this.contactId,
    required this.contactName,
  });

  final String contactId;
  final String contactName;

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    BankDetail? existing,
  }) async {
    final result = await Navigator.of(context).push<BankDetail>(
      MaterialPageRoute<BankDetail>(
        builder: (_) => _BankDetailFormScreen(existing: existing),
      ),
    );
    if (result == null || !context.mounted) return;

    final saved = await ref.read(bankChatProvider(contactId).notifier).save(
      result,
    );
    if (!context.mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bank Chat already holds $kMaxBankDetails sets of details. '
            'Delete one to add another.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BankDetail detail,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete these details?'),
        content: Text(
          '${detail.title}\'s banking details will be removed from this '
          'device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(bankChatProvider(contactId).notifier).delete(detail.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(bankChatProvider(contactId));
    final isFull = details.length >= kMaxBankDetails;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Bank Chat',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: const AppBackButton.appBar(),
        leadingWidth: AppBackButton.leadingWidth,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (contactName.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  contactName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            // Said plainly and up front: these are account numbers, and the
            // user deserves to know where they are being kept.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.mutedGray,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phonelink_lock_outlined,
                    size: 20,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Saved on this phone only. Never sent to a bank or to '
                      'the internet — so it is not backed up either.',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (details.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mutedGray,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.account_balance_outlined,
                        color: AppColors.primaryBlue,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No banking details yet',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add up to $kMaxBankDetails sets of details, then copy '
                      'any field straight into your banking app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...details.map(
                (detail) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _BankDetailCard(
                    detail: detail,
                    onEdit: () => _openForm(context, ref, existing: detail),
                    onDelete: () => _confirmDelete(context, ref, detail),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            CustomButton(
              label: isFull
                  ? 'Maximum $kMaxBankDetails reached'
                  : 'Add Banking Details',
              icon: isFull ? null : Icons.add_rounded,
              onPressed: isFull ? null : () => _openForm(context, ref),
              enabled: !isFull,
              height: 52,
            ),
            if (isFull)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Delete a set of details above to make room for another.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One set of details: heading, a copy-everything action, and the six fields.
class _BankDetailCard extends StatelessWidget {
  const _BankDetailCard({
    required this.detail,
    required this.onEdit,
    required this.onDelete,
  });

  final BankDetail detail;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Future<void> _copyAll(BuildContext context) async {
    final text = detail.toClipboardText();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All details copied'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _copyAll(context),
                icon: const Icon(Icons.content_copy_rounded, size: 16),
                label: const Text('Copy all'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          CopyableField(label: 'Bank Name', value: detail.bankName),
          CopyableField(label: 'Account Type', value: detail.accountType),
          CopyableField(
            label: 'Account Number',
            value: detail.accountNumber,
            groupDigits: true,
          ),
          CopyableField(
            label: 'Branch Code',
            value: detail.branchCode,
            groupDigits: true,
          ),
          CopyableField(label: 'Account Holder', value: detail.accountHolder),
          CopyableField(
            label: 'Reference',
            value: detail.reference,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

/// Add / edit form. Pops the built [BankDetail]; the caller persists it.
class _BankDetailFormScreen extends StatefulWidget {
  const _BankDetailFormScreen({this.existing});

  final BankDetail? existing;

  @override
  State<_BankDetailFormScreen> createState() => _BankDetailFormScreenState();
}

class _BankDetailFormScreenState extends State<_BankDetailFormScreen> {
  /// The account types South African banks actually offer. Offered as taps
  /// because "Cheque" vs "Current" vs "Transmission" is exactly the sort of
  /// thing a payer guesses at and gets wrong.
  static const List<String> _accountTypes = [
    'Cheque / Current',
    'Savings',
    'Transmission',
    'Business',
  ];

  late final TextEditingController _bankName;
  late final TextEditingController _accountType;
  late final TextEditingController _accountNumber;
  late final TextEditingController _branchCode;
  late final TextEditingController _accountHolder;
  late final TextEditingController _reference;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _bankName = TextEditingController(text: e?.bankName ?? '');
    _accountType = TextEditingController(text: e?.accountType ?? '');
    _accountNumber = TextEditingController(text: e?.accountNumber ?? '');
    _branchCode = TextEditingController(text: e?.branchCode ?? '');
    _accountHolder = TextEditingController(text: e?.accountHolder ?? '');
    _reference = TextEditingController(text: e?.reference ?? '');
  }

  @override
  void dispose() {
    _bankName.dispose();
    _accountType.dispose();
    _accountNumber.dispose();
    _branchCode.dispose();
    _accountHolder.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _save() {
    final detail = BankDetail(
      id:
          widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      bankName: _bankName.text.trim(),
      accountType: _accountType.text.trim(),
      accountNumber: _accountNumber.text.trim(),
      branchCode: _branchCode.text.trim(),
      accountHolder: _accountHolder.text.trim(),
      reference: _reference.text.trim(),
    );
    if (detail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in at least one field.')),
      );
      return;
    }
    Navigator.of(context).pop(detail);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final branchSuggestions = suggestBranchCodes(
      _branchCode.text,
      bankName: _bankName.text,
    ).take(6).toList();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          isEditing ? 'Edit Banking Details' : 'Add Banking Details',
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: const AppBackButton.appBar(),
        leadingWidth: AppBackButton.leadingWidth,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _FormField(
              label: 'Bank Name',
              controller: _bankName,
              hint: 'e.g. Capitec Bank',
              textCapitalization: TextCapitalization.words,
              // Retyped so the branch-code suggestions re-rank as the bank
              // is named — the whole point of suggesting them.
              onChanged: (_) => setState(() {}),
            ),
            _SuggestionChips(
              suggestions: [
                for (final b in kSaBranchCodes.take(8)) b.bankName,
              ],
              onSelected: (name) {
                final match = kSaBranchCodes.firstWhere(
                  (b) => b.bankName == name,
                );
                setState(() {
                  _bankName.text = match.bankName;
                  // Only fill an empty code: never overwrite something the
                  // user has already typed in.
                  if (_branchCode.text.trim().isEmpty) {
                    _branchCode.text = match.code;
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            _FormField(
              label: 'Account Type',
              controller: _accountType,
              hint: 'e.g. Savings',
              textCapitalization: TextCapitalization.words,
            ),
            _SuggestionChips(
              suggestions: _accountTypes,
              onSelected: (type) =>
                  setState(() => _accountType.text = type),
            ),
            const SizedBox(height: 16),
            _FormField(
              label: 'Account Number',
              controller: _accountNumber,
              hint: 'Digits only',
              keyboardType: TextInputType.number,
              // Digits only, and no length cap: SA account numbers run from 7
              // to 11 digits depending on the bank, and capping at the
              // commonest length would silently truncate the others.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            _FormField(
              label: 'Branch Code',
              controller: _branchCode,
              hint: 'e.g. 470010',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            const Text(
              'Universal branch codes — tap one to use it',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            if (branchSuggestions.isEmpty)
              const Text(
                'No match. You can still type the code your bank gave you.',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              )
            else
              ...branchSuggestions.map(
                (s) => InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() {
                    _branchCode.text = s.code;
                    if (_bankName.text.trim().isEmpty) {
                      _bankName.text = s.bankName;
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.bankName,
                            style: const TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          s.code,
                          style: const TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _FormField(
              label: 'Account Holder',
              controller: _accountHolder,
              hint: 'Name on the account',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            _FormField(
              label: 'Reference',
              controller: _reference,
              hint: 'What the payer should put as reference',
            ),
            const SizedBox(height: 28),
            CustomButton(
              label: isEditing ? 'Save Changes' : 'Save Details',
              onPressed: _save,
              height: 52,
            ),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primaryBlue,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontal row of tappable shortcuts under a field.
class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({required this.suggestions, required this.onSelected});

  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onSelected(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.mutedGray,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The "Bank Chat" entry point, placed under the Notes section on both the
/// saved-contact screen and the incoming-call sheet.
///
/// A [ConsumerWidget] so it can show how many sets of details are stored
/// without its host having to be one — the incoming-call sheet is a plain
/// presentational widget.
class BankChatButton extends ConsumerWidget {
  const BankChatButton({
    super.key,
    required this.contactId,
    required this.contactName,
    this.compact = false,
  });

  final String contactId;
  final String contactName;

  /// Tighter padding and type for the incoming-call sheet, where vertical
  /// space is scarce.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An unsaved contact (an ad-hoc dialled number, an unknown caller) has no
    // id to store details against, so there is nothing to offer. Same when
    // the device has no local store — better to not offer Bank Chat at all
    // than to open a screen that cannot save.
    if (contactId.isEmpty) return const SizedBox.shrink();
    if (!ref.watch(bankChatAvailableProvider)) return const SizedBox.shrink();

    final count = ref.watch(bankChatProvider(contactId)).length;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BankChatScreen(
            contactId: contactId,
            contactName: contactName,
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 11 : 14,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryBlue, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 34 : 40,
              height: compact ? 34 : 40,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.account_balance_outlined,
                size: compact ? 18 : 21,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bank Chat',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: compact ? 14 : 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count == 0
                        ? 'Add banking details to copy'
                        : '$count of $kMaxBankDetails saved · tap to copy',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: compact ? 11 : 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}
