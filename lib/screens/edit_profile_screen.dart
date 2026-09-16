import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:metadata/core/bootstrap/auth_gate.dart';
import 'package:metadata/core/firebase/firebase_providers.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/screens/change_phone_number_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/contact_avatar.dart';

/// Everything about the account the user can change, in one place: photo,
/// name, and number.
///
/// Profile used to carry three separate edit affordances — a camera badge on
/// the avatar, a pen beside the name, a pen beside the number — each opening
/// something different (a sheet, a dialog, a whole screen). This replaces all
/// three with one form.
///
/// Photo and name are staged locally and committed together by Save, so the
/// screen behaves like a form rather than three independent controls. The
/// number is the exception and cannot work that way: it is the credential the
/// account signs in with, so a new one has to receive a code before it can
/// replace the old one. It gets a "Change" action that opens
/// [ChangePhoneNumberScreen] and commits on its own.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

enum _PhotoAction { camera, gallery, remove }

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();

  /// Set once from the profile stream's first non-null value. Without this the
  /// field would be rewritten — and the cursor thrown to the start — every
  /// time the Firestore snapshot re-emitted while the user was typing.
  bool _nameInitialized = false;
  String _initialName = '';

  /// Staged photo edits. Neither touches Storage until Save.
  File? _pickedPhoto;
  bool _removeExistingPhoto = false;

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges {
    if (_pickedPhoto != null || _removeExistingPhoto) return true;
    return _nameController.text.trim() != _initialName.trim();
  }

  Future<void> _pickPhoto({required bool hasPhoto}) async {
    final choice = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.gallery),
            ),
            // A "Remove Photo" row on an account with none is a dead control.
            if (hasPhoto)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == _PhotoAction.remove) {
      setState(() {
        _pickedPhoto = null;
        _removeExistingPhoto = true;
      });
      return;
    }

    final pickedFile = await _imagePicker.pickImage(
      source: choice == _PhotoAction.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // A full-resolution phone camera shot is several megabytes, which on a
      // mobile connection reliably outruns the save timeout and reads to the
      // user as "uploading is broken". An avatar is never shown above ~110pt.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (pickedFile == null || !mounted) return;

    setState(() {
      _pickedPhoto = File(pickedFile.path);
      _removeExistingPhoto = false;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    // An empty name would send the user back through the name-setup gate on
    // next launch, so it is rejected rather than saved.
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a name.')));
      return;
    }
    if (!_hasUnsavedChanges) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    AppLoading.show();
    final service = ref.read(userProfileServiceProvider);
    // Captured before the awaits: the success path pops this route, so
    // looking either of these up off `context` afterwards is a use of a
    // context whose widget is already on its way out.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Photo first: it is the failure-prone half (large upload, Storage
      // rules, bucket setup), and finishing it before the name write means a
      // photo failure never leaves the name silently unsaved too.
      if (_removeExistingPhoto) {
        await service.removeProfilePhoto().timeout(const Duration(seconds: 25));
      } else {
        final file = _pickedPhoto;
        if (file != null) {
          final url = await service
              .uploadProfilePhoto(file)
              .timeout(const Duration(seconds: 45));
          // Storage reuses the object path, so a re-upload can come back on a
          // URL Flutter already has cached — without this the old picture
          // stays on screen and the upload looks like it did nothing.
          await NetworkImage(url).evict();
        }
      }

      if (name != _initialName.trim()) {
        await service
            .updateDisplayName(name)
            .timeout(const Duration(seconds: 20));
      }

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(SnackBar(content: Text(_saveErrorMessage(e))));
    } finally {
      AppLoading.dismiss();
    }
  }

  /// Storage failures are the ones most likely to be a project-configuration
  /// problem rather than anything the user did, so they get told which.
  String _saveErrorMessage(Object e) {
    if (e is TimeoutException) {
      return 'This is taking too long. Check your connection and try again.';
    }
    if (e is FirebaseException) {
      return switch (e.code) {
        'unauthorized' =>
          'Storage rejected the upload. The Storage security rules need to '
              'allow users/{uid}/**.',
        'object-not-found' || 'bucket-not-found' =>
          'No Storage bucket is set up for this project yet.',
        'canceled' => 'Upload cancelled.',
        'retry-limit-exceeded' =>
          'The upload kept failing. Check your connection and try again.',
        'permission-denied' =>
          'Firestore rejected the change (permission-denied).',
        _ => 'Could not save your profile (${e.code}).',
      };
    }
    return 'Could not save your profile: $e';
  }

  Future<void> _confirmDiscard() async {
    if (!_hasUnsavedChanges) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits have not been saved yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Discard',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileStreamProvider).value;

    if (!_nameInitialized && profile != null) {
      _nameInitialized = true;
      _initialName = profile.displayName;
      _nameController.text = profile.displayName;
    }

    // The profile doc's number is written once at sign-up, so it can be empty
    // for an account created another way. The auth record is authoritative for
    // a phone-auth account, and is already there while the doc is loading.
    final authPhoneNumber = ref
        .watch(firebaseAuthProvider)
        .currentUser
        ?.phoneNumber;
    final phoneNumber = (profile?.phoneNumber.isNotEmpty ?? false)
        ? profile!.phoneNumber
        : (authPhoneNumber ?? '');

    final storedPhotoUrl = profile?.photoUrl;
    final showsAPhoto =
        _pickedPhoto != null ||
        (!_removeExistingPhoto && (storedPhotoUrl ?? '').isNotEmpty);

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'Edit Profile',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          leading: AppBackButton.appBar(onPressed: _confirmDiscard),
          leadingWidth: AppBackButton.leadingWidth,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () => _pickPhoto(hasPhoto: showsAPhoto),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ContactAvatar(
                        diameter: 110,
                        localFile: _pickedPhoto,
                        photoUrl: _removeExistingPhoto
                            ? null
                            : (_pickedPhoto == null ? storedPhotoUrl : null),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.white,
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _isSaving
                      ? null
                      : () => _pickPhoto(hasPhoto: showsAPhoto),
                  child: Text(
                    showsAPhoto ? 'Change Photo' : 'Add Photo',
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ),
              if (_removeExistingPhoto)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Photo will be removed when you save.',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const _FieldLabel('Full Name'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Your name',
                  hintStyle: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    color: AppColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: AppColors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const _FieldLabel('Phone Number'),
              const SizedBox(height: 8),
              // Read-only on purpose. This is the credential the account signs
              // in with, so it cannot be typed over the way a name can — the
              // new number has to receive a code first.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mutedGray,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.phone_iphone_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        phoneNumber.isNotEmpty
                            ? phoneNumber
                            : 'No number on this account',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: phoneNumber.isNotEmpty
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).push<bool>(
                              MaterialPageRoute<bool>(
                                builder: (_) => ChangePhoneNumberScreen(
                                  currentPhoneNumber: phoneNumber,
                                ),
                              ),
                            ),
                      child: Text(
                        phoneNumber.isNotEmpty ? 'Change' : 'Add',
                        style: const TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Changing your number needs a verification code, so it is '
                'saved separately from the rest of this form.',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              CustomButton(
                label: _isSaving ? 'Saving...' : 'Save Changes',
                onPressed: _isSaving || !_hasUnsavedChanges ? null : _save,
                enabled: !_isSaving && _hasUnsavedChanges,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'SF Pro Display',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}
