import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/repositories/call_flow_helper.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/contact_fab_column.dart';
import 'package:metadata/widgets/contact_tile.dart';
import 'package:metadata/widgets/quarantine_badge.dart';
import 'package:skeletonizer/skeletonizer.dart';

final List<ContactModel> _kSkeletonContacts = List.generate(
  6,
  (i) => ContactModel(
    id: 'skeleton-$i',
    fullName: 'Loading Name',
    phoneNumber: '+1 000 000 0000',
    updatedAt: DateTime.now(),
  ),
);

/// The three tabs, in display order — also the index each one occupies.
enum ContactsTab { all, captured, manual }

/// "Saved Contacts" screen reached from Home's "View Saved Contact" button
/// — previously that button jumped straight into a single contact's
/// details; per the design it should open this tabbed picker instead.
class SavedContactsScreen extends ConsumerStatefulWidget {
  const SavedContactsScreen({super.key, this.initialTab = ContactsTab.all});

  /// Which tab opens first. Profile's stat cards use this to land on the tab
  /// whose count the user just tapped.
  final ContactsTab initialTab;

  @override
  ConsumerState<SavedContactsScreen> createState() =>
      _SavedContactsScreenState();
}

class _SavedContactsScreenState extends ConsumerState<SavedContactsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Contacts picked for bulk delete, by id. Held by id rather than by model
  /// so a selection survives the contact stream re-emitting, and so it spans
  /// tabs: pick some in Captured, switch to Manual, pick more, delete once.
  final Set<String> _selectedIds = {};

  bool get _isSelecting => _selectedIds.isNotEmpty;

  static const _tabLabels = ['All Contacts', 'Captured', 'Manual'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    // TabBarView swipes change _tabController.index without otherwise
    // notifying this widget — repaint the pill bar so it stays in sync.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelected(ContactModel contact) {
    setState(() {
      if (!_selectedIds.remove(contact.id)) _selectedIds.add(contact.id);
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  Future<void> _deleteSelected(List<ContactModel> allContacts) async {
    final ids = Set<String>.from(_selectedIds);
    if (ids.isEmpty) return;
    final names = allContacts
        .where((c) => ids.contains(c.id))
        .map((c) => c.fullName)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          ids.length == 1 ? 'Delete Contact' : 'Delete ${ids.length} Contacts',
        ),
        content: Text(
          ids.length == 1
              ? 'Delete ${names.isEmpty ? 'this contact' : names.single}, '
                    'along with its notes and timeline?'
              : 'Delete these ${ids.length} contacts, along with their notes '
                    'and timelines?',
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
    if (confirmed != true || !mounted) return;

    AppLoading.show();
    final repository = ref.read(contactRepositoryProvider);
    final failed = <String>[];
    try {
      for (final id in ids) {
        try {
          await repository
              .deleteContact(id)
              .timeout(const Duration(seconds: 20));
        } catch (_) {
          // Keep going: one unreachable contact shouldn't strand the rest of
          // the batch half-deleted with no way to retry.
          failed.add(id);
        }
      }
    } finally {
      AppLoading.dismiss();
    }

    if (!mounted) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(failed);
    });
    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed.length == 1
                ? 'One contact could not be deleted.'
                : '${failed.length} contacts could not be deleted.',
          ),
        ),
      );
    }
  }

  List<ContactModel> _filter(List<ContactModel> contacts) {
    var result = contacts;
    if (_query.isNotEmpty) {
      final query = _query.toLowerCase();
      result = result
          .where(
            (c) =>
                c.fullName.toLowerCase().contains(query) ||
                c.phoneNumber.toLowerCase().contains(query),
          )
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(allContactsProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _isSelecting ? '${_selectedIds.length} selected' : 'Your Contacts',
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        // While selecting, Back would read as "go back a screen"; the close
        // button drops the selection instead and leaves the screen put.
        leading: _isSelecting
            ? IconButton(
                onPressed: _clearSelection,
                tooltip: 'Cancel selection',
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.primaryBlue,
                ),
              )
            : const AppBackButton.appBar(),
        leadingWidth: _isSelecting ? null : AppBackButton.leadingWidth,
        actions: [
          if (_isSelecting)
            IconButton(
              onPressed: () => _deleteSelected(contactsAsync.value ?? const []),
              tooltip: 'Delete selected',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number',
                  hintStyle: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    color: AppColors.textSecondary,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: AppColors.mutedGray,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.lightBlueFill,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: List.generate(_tabLabels.length, (index) {
                    final isActive = _tabController.index == index;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _tabController.animateTo(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.primaryBlue
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _tabLabels[index],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isActive
                                  ? Colors.white
                                  : AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: contactsAsync.when(
                  loading: () => _buildSkeletonList(),
                  error: (error, _) =>
                      Center(child: Text('Could not load contacts: $error')),
                  data: (contacts) {
                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(_filter(contacts)),
                        _buildList(
                          _filter(contacts.where((c) => c.isCaptured).toList()),
                          emptyMessage:
                              'No contacts saved with Capture Context '
                              'Automatically yet.',
                        ),
                        _buildList(
                          _filter(
                            contacts.where((c) => c.isManuallySaved).toList(),
                          ),
                          emptyMessage: 'No manually saved contacts yet.',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      // The delete action lives in the app bar while selecting; the add
      // and dial FABs would only compete with it.
      floatingActionButton: _isSelecting ? null : const ContactFabColumn(),
    );
  }

  Widget _buildList(
    List<ContactModel> contacts, {
    String emptyMessage = 'No contacts yet.',
  }) {
    return _ContactsList(
      contacts: contacts,
      emptyMessage: emptyMessage,
      selectedIds: _selectedIds,
      isSelecting: _isSelecting,
      onToggleSelected: _toggleSelected,
    );
  }

  Widget _buildSkeletonList() {
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        itemCount: _kSkeletonContacts.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => ContactTile(
          contact: _kSkeletonContacts[index],
          subtitle: const Text(
            '+1 000 000 0000',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          onCallTap: () {},
          onFavoriteTap: () {},
        ),
      ),
    );
  }
}

class _ContactsList extends ConsumerWidget {
  const _ContactsList({
    required this.contacts,
    this.emptyMessage = 'No contacts yet.',
    required this.selectedIds,
    required this.isSelecting,
    required this.onToggleSelected,
  });

  final List<ContactModel> contacts;
  final String emptyMessage;
  final Set<String> selectedIds;
  final bool isSelecting;
  final void Function(ContactModel contact) onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (contacts.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return ContactTile(
          contact: contact,
          subtitle: Text(
            contact.phoneNumber,
            style: const TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          selected: isSelecting ? selectedIds.contains(contact.id) : null,
          // Long-press anywhere in the list starts a selection; after that a
          // plain tap picks rows instead of opening them.
          onLongPress: () => onToggleSelected(contact),
          onTap: isSelecting
              ? () => onToggleSelected(contact)
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SavedContactDetailsScreen(contactId: contact.id),
                    ),
                  );
                },
          onCallTap: () => initiateCall(context, ref, contact),
          onFavoriteTap: () => toggleContactFavorite(ref, contact),
          onQuarantineTap: () =>
              reviewQuarantinedContact(context, ref, contact),
        );
      },
    );
  }
}
