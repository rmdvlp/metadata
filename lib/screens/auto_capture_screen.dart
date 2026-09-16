import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/navigation/contact_capture_flow.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/contact_avatar.dart';
import 'package:skeletonizer/skeletonizer.dart';

final List<ContactModel> _kSkeletonContacts = List.generate(
  5,
  (i) => ContactModel(
    id: 'skeleton-$i',
    fullName: 'Loading Name',
    phoneNumber: '+1 000 000 0000',
    updatedAt: DateTime.now(),
  ),
);

/// Picks someone already in your contacts (synced from the device address book
/// or added previously) and jumps straight into the location/time capture step,
/// skipping name/phone entry entirely.
///
/// No longer wired to the "Auto Capture" option in the Add New Contact popup —
/// that now opens the New Contact form and continues into capture from there
/// (see [ContactSaveFlow.captureContext]). Kept because capturing context for an
/// existing contact is still a distinct, useful action; currently unreferenced
/// outside tests.
class AutoCaptureScreen extends ConsumerStatefulWidget {
  const AutoCaptureScreen({super.key});

  @override
  ConsumerState<AutoCaptureScreen> createState() => _AutoCaptureScreenState();
}

class _AutoCaptureScreenState extends ConsumerState<AutoCaptureScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ContactModel> _filter(List<ContactModel> contacts) {
    if (_query.isEmpty) return contacts;
    final query = _query.toLowerCase();
    return contacts
        .where(
          (c) =>
              c.fullName.toLowerCase().contains(query) ||
              c.phoneNumber.toLowerCase().contains(query),
        )
        .toList();
  }

  void _selectContact(ContactModel contact) {
    continueContactCaptureFlow(context, ref, contact.id);
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
        title: const Text(
          'Auto Capture',
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pick a contact and we\'ll automatically capture the address, '
                'venue name, and exact time of this encounter.',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
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
              Expanded(
                child: contactsAsync.when(
                  loading: () => Skeletonizer(
                    enabled: true,
                    child: ListView.separated(
                      itemCount: _kSkeletonContacts.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _PickerTile(
                        contact: _kSkeletonContacts[index],
                        onTap: () {},
                        onFavoriteTap: () {},
                      ),
                    ),
                  ),
                  error: (error, _) => Center(child: Text('Could not load contacts: $error')),
                  data: (contacts) {
                    final filtered = _filter(contacts);
                    if (contacts.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'No contacts found yet. Grant contacts access from your '
                            'phone\'s address book, or use "Save Manually" instead.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text(
                          'No contacts match your search.',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final contact = filtered[index];
                        return _PickerTile(
                          contact: contact,
                          onTap: () => _selectContact(contact),
                          onFavoriteTap: () => toggleContactFavorite(ref, contact),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.contact,
    required this.onTap,
    required this.onFavoriteTap,
  });

  final ContactModel contact;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.mutedGray,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ContactAvatar(
              diameter: 44,
              photoUrl: contact.photoUrl,
              isFavorite: contact.isFavorite,
              onFavoriteTap: onFavoriteTap,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.phoneNumber,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 12,
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
