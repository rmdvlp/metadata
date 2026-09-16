import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/models/note_entry.dart';
import 'package:metadata/models/timeline_entry.dart';
import 'package:metadata/repositories/call_flow_helper.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/screens/add_encounter_screen.dart';
import 'package:metadata/screens/bank_chat_screen.dart';
import 'package:metadata/screens/capture_context.dart';
import 'package:metadata/screens/contact_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/contact_quarantine.dart';
import 'package:metadata/utils/date_formatting.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/contact_avatar.dart';
import 'package:metadata/widgets/quarantine_badge.dart';
import 'package:skeletonizer/skeletonizer.dart';

final ContactModel _kSkeletonContact = ContactModel(
  id: 'skeleton',
  fullName: 'Loading Name',
  phoneNumber: '+1 000 000 0000',
  updatedAt: DateTime.now(),
);

class SavedContactDetailsScreen extends ConsumerWidget {
  const SavedContactDetailsScreen({super.key, required this.contactId});

  final String contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactAsync = ref.watch(contactByIdProvider(contactId));
    final timelineAsync = ref.watch(contactTimelineProvider(contactId));
    final notesAsync = ref.watch(contactNotesProvider(contactId));

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: contactAsync.when(
          loading: () => Skeletonizer(
            enabled: true,
            child: _SavedContactDetailsBody(
              contact: _kSkeletonContact,
              timeline: const [],
              notes: const [],
            ),
          ),
          error: (error, _) => _DetailsPlaceholder(
            icon: Icons.error_outline_rounded,
            title: 'Could not load this contact',
            message: '$error',
          ),
          data: (contact) {
            if (contact == null) {
              // Reachable whenever the contact is gone but the route isn't —
              // e.g. opening a Home call-log row for a contact deleted on
              // another device. Must never be a bare message: without the
              // header below there is no way back off this screen.
              return const _DetailsPlaceholder(
                icon: Icons.person_off_outlined,
                title: 'Contact no longer available',
                message:
                    'This contact has been deleted. Its call history is still '
                    'on your Home screen.',
              );
            }
            final timeline = timelineAsync.value ?? const <TimelineEntry>[];
            final notes = notesAsync.value ?? const <NoteEntry>[];
            return _SavedContactDetailsBody(
              contact: contact,
              timeline: timeline,
              notes: notes,
            );
          },
        ),
      ),
    );
  }
}

class _SavedContactDetailsBody extends ConsumerWidget {
  const _SavedContactDetailsBody({
    required this.contact,
    required this.timeline,
    required this.notes,
  });

  final ContactModel contact;
  final List<TimelineEntry> timeline;
  final List<NoteEntry> notes;

  void _openAddEncounter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddEncounterScreen(contactId: contact.id),
      ),
    );
  }

  void _openEditEncounter(BuildContext context, TimelineEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AddEncounterScreen(contactId: contact.id, existing: entry),
      ),
    );
  }

  Future<void> _deleteTimelineEntry(
    BuildContext context,
    WidgetRef ref,
    TimelineEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Timeline Entry'),
        content: Text('Delete "${entry.title}" from this contact\'s timeline?'),
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

    AppLoading.show();
    try {
      await ref
          .read(contactRepositoryProvider)
          .deleteTimelineEntry(contact.id, entry.id)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete this entry: $e')),
      );
    } finally {
      AppLoading.dismiss();
    }
  }

  /// Shared by adding a note, editing one, and editing the contact's own note
  /// field, so all three take the same text and the same buttons. Returns the
  /// trimmed text, or null if the user cancelled or left it empty.
  Future<String?> _promptForNoteText(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String initialText = '',
  }) async {
    final textController = TextEditingController(text: initialText);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          minLines: 2,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Write a note about this contact',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (confirmed != true) return null;
    final text = textController.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Runs a note write behind the blocking loader, reporting failures the same
  /// way for every note action.
  Future<void> _runNoteWrite(
    BuildContext context,
    Future<void> Function() write,
    String failureMessage,
  ) async {
    AppLoading.show();
    try {
      await write().timeout(const Duration(seconds: 20));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$failureMessage: $e')));
    } finally {
      AppLoading.dismiss();
    }
  }

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    final text = await _promptForNoteText(
      context,
      title: 'Add Note',
      confirmLabel: 'Add',
    );
    if (text == null || !context.mounted) return;

    await _runNoteWrite(
      context,
      () => ref.read(contactRepositoryProvider).addNote(contact.id, text),
      'Could not add this note',
    );
  }

  Future<void> _editNote(
    BuildContext context,
    WidgetRef ref,
    NoteEntry note,
  ) async {
    final text = await _promptForNoteText(
      context,
      title: 'Edit Note',
      confirmLabel: 'Save',
      initialText: note.text,
    );
    if (text == null || text == note.text || !context.mounted) return;

    await _runNoteWrite(
      context,
      () => ref
          .read(contactRepositoryProvider)
          .updateNote(contact.id, note.id, text),
      'Could not update this note',
    );
  }

  /// The single free-text note captured on the add/edit contact form, which
  /// lives on the contact document rather than in the notes subcollection.
  Future<void> _editContactNote(BuildContext context, WidgetRef ref) async {
    final text = await _promptForNoteText(
      context,
      title: 'Edit Note',
      confirmLabel: 'Save',
      initialText: contact.notes ?? '',
    );
    if (text == null || text == contact.notes || !context.mounted) return;

    await _runNoteWrite(
      context,
      () => ref.read(contactRepositoryProvider).updateContact(contact.id, {
        'notes': text,
      }),
      'Could not update this note',
    );
  }

  /// Clears the contact's own note field. Written as null rather than an empty
  /// string so the details screen's "is there a note" check treats it exactly
  /// like a contact that never had one.
  Future<void> _deleteContactNote(BuildContext context, WidgetRef ref) async {
    await _runNoteWrite(
      context,
      () => ref.read(contactRepositoryProvider).updateContact(contact.id, {
        'notes': null,
      }),
      'Could not delete this note',
    );
  }

  Future<void> _deleteNote(
    BuildContext context,
    WidgetRef ref,
    NoteEntry note,
  ) async {
    AppLoading.show();
    try {
      await ref
          .read(contactRepositoryProvider)
          .deleteNote(contact.id, note.id)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete this note: $e')));
    } finally {
      AppLoading.dismiss();
    }
  }

  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(contactRepositoryProvider).updateContact(contact.id, {
        'isFavorite': !contact.isFavorite,
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update favorite status: $e')),
      );
    }
  }

  Future<void> _toggleBlockContact(BuildContext context, WidgetRef ref) async {
    final blocking = !contact.isBlocked;

    // Only blocking needs a warning; unblocking is harmless and immediate.
    if (blocking) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Block Contact'),
          content: Text(
            'Block ${contact.fullName}? Their calls will stop showing a call '
            'card or notification here. Your phone will still ring — this app '
            'is not your default dialer, so it cannot stop the call itself.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Block',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    AppLoading.show();
    try {
      await ref
          .read(contactRepositoryProvider)
          .updateContact(contact.id, {'isBlocked': blocking})
          .timeout(const Duration(seconds: 20));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocking
                ? '${contact.fullName} blocked.'
                : '${contact.fullName} unblocked.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocking
                ? 'Could not block this contact: $e'
                : 'Could not unblock this contact: $e',
          ),
        ),
      );
    } finally {
      AppLoading.dismiss();
    }
  }

  /// Opens the "Keep or Remove Contact?" review from the pill under the
  /// photo. The Navigator is resolved up front: a delete makes this screen's
  /// contact stream emit null, and by then this context is on its way out.
  Future<void> _reviewQuarantine(BuildContext context, WidgetRef ref) {
    final navigator = Navigator.of(context);
    return reviewQuarantinedContact(
      context,
      ref,
      contact,
      onDeleted: navigator.pop,
    );
  }

  Future<void> _confirmDeleteContact(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text(
          'Delete ${contact.fullName}? This will permanently remove this contact, '
          'along with its notes and timeline.',
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

    // Resolved before the await: deleting the doc makes the contact stream
    // emit null, which tears this widget out of the tree. Reading the
    // Navigator afterwards would find an unmounted context and skip the pop,
    // stranding the user on the "contact not found" screen.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final deletedName = contact.fullName;

    AppLoading.show();
    try {
      await ref
          .read(contactRepositoryProvider)
          .deleteContact(contact.id)
          .timeout(const Duration(seconds: 20));
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('$deletedName deleted.')));
      return;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete this contact: $e')),
      );
    } finally {
      AppLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = contact.location;
    final eventDate = contact.eventDate;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            const AppBackButton(),
            const Expanded(
              child: Text(
                'Saved Contact Details',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            _ContactActionsMenu(
              isBlocked: contact.isBlocked,
              onBlockToggle: () => _toggleBlockContact(context, ref),
              onDelete: () => _confirmDeleteContact(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: ContactAvatar(
            diameter: 130,
            photoUrl: contact.photoUrl,
            isFavorite: contact.isFavorite,
            onFavoriteTap: () => _toggleFavorite(context, ref),
          ),
        ),
        // Sits under the photo rather than overlapping it as in the design:
        // the avatar's favorite heart already occupies that bottom edge, and
        // two badges fighting for the same corner would obscure both.
        if (isQuarantined(contact))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: QuarantineBadge(
                large: true,
                onTap: () => _reviewQuarantine(context, ref),
              ),
            ),
          ),
        const SizedBox(height: 14),
        Text(
          contact.fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          contact.phoneNumber,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
        if (contact.isBlocked) ...[
          const SizedBox(height: 16),
          _BlockedBanner(onUnblock: () => _toggleBlockContact(context, ref)),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ContactScreen(contact: contact),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.lightBlueFill,
                    foregroundColor: AppColors.primaryBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text(
                    'Edit',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  // Matches the disabled call action on blocked list rows —
                  // the banner above says why and offers the way out.
                  onPressed: contact.isBlocked
                      ? null
                      : () => initiateCall(
                          context,
                          ref,
                          contact,
                          timeline: timeline,
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.lightGray,
                    disabledForegroundColor: AppColors.textSecondary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: Text(
                    contact.isBlocked ? 'Blocked' : 'Call',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Contextual memory — encounter details, notes, and timeline.
        // Shown for every contact regardless of how it was saved: a
        // manually saved contact can be given a location, notes and
        // timeline entries later, so hiding these would put that out of
        // reach.
        const SizedBox(height: 24),
        const Text(
          'Encounter Details',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.mutedGray,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      location?.placeName ??
                          location?.address ??
                          'Not captured yet',
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CaptureContextScreen(contactId: contact.id),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location?.address ?? 'No address captured',
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Longitude: ',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    location != null
                        ? '${location.lng.toStringAsFixed(4)}°'
                        : '—',
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 14, color: AppColors.border),
                  const SizedBox(width: 12),
                  const Text(
                    'Latitude: ',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    location != null
                        ? '${location.lat.toStringAsFixed(4)}°'
                        : '—',
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoIconBlock(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: eventDate != null ? formatShortDate(eventDate) : '—',
                  ),
                  const SizedBox(width: 24),
                  _InfoIconBlock(
                    icon: Icons.access_time_rounded,
                    label: 'Time',
                    value: eventDate != null ? formatTime(eventDate) : '—',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Notes',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            InkWell(
              onTap: () => _addNote(context, ref),
              child: const Text(
                'Add Note',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (contact.notes != null && contact.notes!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.mutedGray,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    contact.notes!,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                _NoteMenu(
                  onEdit: () => _editContactNote(context, ref),
                  onDelete: () => _deleteContactNote(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (notes.isEmpty && (contact.notes == null || contact.notes!.isEmpty))
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.mutedGray,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'No notes added yet.',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          )
        else
          ...notes.map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mutedGray,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        note.text,
                        style: const TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _NoteMenu(
                      onEdit: () => _editNote(context, ref, note),
                      onDelete: () => _deleteNote(context, ref, note),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        // Directly under Notes: the two are used together — a note says who
        // the person is, Bank Chat holds what you need to pay them.
        BankChatButton(contactId: contact.id, contactName: contact.fullName),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Timeline',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            InkWell(
              onTap: () => _openAddEncounter(context),
              child: const Text(
                'Add New',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (timeline.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.mutedGray,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'No timeline entries yet.',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.mutedGray,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: List.generate(timeline.length, (index) {
                final entry = timeline[index];
                return _TimelineTile(
                  entry: entry,
                  isLast: index == timeline.length - 1,
                  onEdit: () => _openEditEncounter(context, entry),
                  onDelete: () => _deleteTimelineEntry(context, ref, entry),
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// Explains the blocked state in place and offers the way out of it, so a
/// disabled Call button is never unexplained.
class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner({required this.onUnblock});

  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.block_rounded, size: 20, color: Colors.redAccent),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'You blocked this contact. Their calls won\'t show a call card '
              'here, but your phone will still ring.',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: onUnblock,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Unblock',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stand-in for the details body when there is no contact to show — deleted,
/// or failed to load. Carries its own back arrow because the normal header
/// lives inside the body, so without one these states are a dead end.
class _DetailsPlaceholder extends StatelessWidget {
  const _DetailsPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [const AppBackButton()]),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: AppColors.mutedGray,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: AppColors.textSecondary, size: 26),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Go Back',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Three-dot overflow in the details header. Holds the actions that are rare
/// and/or destructive, so neither can be hit by a stray tap on the way back.
class _ContactActionsMenu extends StatelessWidget {
  const _ContactActionsMenu({
    required this.isBlocked,
    required this.onBlockToggle,
    required this.onDelete,
  });

  final bool isBlocked;
  final VoidCallback onBlockToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      tooltip: 'More actions',
      position: PopupMenuPosition.under,
      // The default 256px max is a hair too narrow for "Unblock Contact" at
      // this weight, which clips the label.
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: AppColors.white,
      onSelected: (value) {
        if (value == 'block') onBlockToggle();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'block',
          child: _ActionRow(
            icon: isBlocked
                ? Icons.check_circle_outline_rounded
                : Icons.block_rounded,
            label: isBlocked ? 'Unblock Contact' : 'Block Contact',
            color: isBlocked ? AppColors.primaryBlue : AppColors.textPrimary,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: _ActionRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete Contact',
            color: Colors.redAccent,
          ),
        ),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: AppColors.mutedGray,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.more_vert_rounded,
          color: AppColors.primaryBlue,
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        // Flexible so a tight menu ellipsizes rather than overflowing.
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoIconBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoIconBlock({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: AppColors.primaryBlue),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Edit/Delete for a note, behind the same ⋮ affordance the timeline rows
/// use. Constrained so its tap target cannot make the row taller than its
/// text.
class _NoteMenu extends StatelessWidget {
  const _NoteMenu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'Note actions',
        icon: const Icon(
          Icons.more_vert_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
        onSelected: (value) {
          if (value == 'edit') onEdit();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

/// Height of a timeline row's header line (label, date, ⋮). Fixed so the rail
/// dot can be centred on it: left to itself the row is as tall as the popup
/// button's 48pt tap target, which floated the label far below the dot.
const double _kTimelineHeaderHeight = 24;

class _TimelineTile extends StatelessWidget {
  final TimelineEntry entry;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TimelineTile({
    required this.entry,
    required this.isLast,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 9,
              child: Column(
                children: [
                  SizedBox(
                    height: _kTimelineHeaderHeight,
                    child: Center(
                      child: Container(
                        key: ValueKey('timeline-dot-${entry.id}'),
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1,
                        color: AppColors.border,
                        margin: const EdgeInsets.only(top: 2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      key: ValueKey('timeline-header-${entry.id}'),
                      height: _kTimelineHeaderHeight,
                      child: Row(
                        children: [
                          // Expanded, not Flexible-plus-Spacer: those two
                          // split the free space evenly and left the date and
                          // menu stranded mid-row instead of hard right.
                          Expanded(
                            child: Text(
                              entry.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryBlue,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.displayDate,
                            style: const TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          // Constrained so its 48pt tap target cannot drive
                          // the header height and knock the row out of line.
                          SizedBox(
                            width: 24,
                            height: _kTimelineHeaderHeight,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              tooltip: 'Entry actions',
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              onSelected: (value) {
                                if (value == 'edit') onEdit();
                                if (value == 'delete') onDelete();
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
