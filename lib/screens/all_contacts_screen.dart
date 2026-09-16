import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/call_flow_helper.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';
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

class AllContactsScreen extends ConsumerStatefulWidget {
  const AllContactsScreen({super.key});

  @override
  ConsumerState<AllContactsScreen> createState() => _AllContactsScreenState();
}

class _AllContactsScreenState extends ConsumerState<AllContactsScreen> {
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
          'All Contacts',
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
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
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
                  ),
                  error: (error, _) =>
                      Center(child: Text('Could not load contacts: $error')),
                  data: (contacts) {
                    final filtered = _filter(contacts);
                    if (contacts.isEmpty) {
                      return const Center(
                        child: Text(
                          'No contacts yet.',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            color: AppColors.textSecondary,
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
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final contact = filtered[index];
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
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SavedContactDetailsScreen(
                                  contactId: contact.id,
                                ),
                              ),
                            );
                          },
                          onCallTap: () => initiateCall(context, ref, contact),
                          onFavoriteTap: () =>
                              toggleContactFavorite(ref, contact),
                          onQuarantineTap: () =>
                              reviewQuarantinedContact(context, ref, contact),
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
