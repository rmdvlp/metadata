import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/core/navigation/contact_capture_flow.dart';
import 'package:metadata/screens/capture_context.dart';
import 'package:metadata/screens/event_detail.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/widgets/contact_avatar.dart';

/// What happens once a brand-new contact has been saved. The user picks by
/// which button they tap at the bottom of the form, rather than up front in a
/// popup — by then they have typed the details and know which they want.
enum ContactSaveFlow {
  /// "Save": name, phone, and notes are the whole job. Saving lands on the new
  /// contact's details with no further steps.
  save,

  /// "Capture Context Automatically": saving continues into the location/time
  /// capture steps.
  captureContext,
}

/// Add-contact form when [contact] is null, edit-contact form otherwise.
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key, this.contact});

  final ContactModel? contact;

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;
  final ImagePicker _imagePicker = ImagePicker();

  String? _newImagePath;
  String? _errorMessage;

  /// Which button is mid-save, so only that one shows a spinner while both
  /// stay disabled. Null when idle.
  ContactSaveFlow? _inFlight;

  bool get _isSaving => _inFlight != null;

  bool get _isEditing => widget.contact != null;

  /// The captured place to show on the location row, if there is one.
  String? get _capturedPlace {
    final place =
        widget.contact?.location?.placeName ?? widget.contact?.location?.address;
    return (place == null || place.isEmpty) ? null : place;
  }

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.contact?.fullName ?? '');
    _phoneController = TextEditingController(text: widget.contact?.phoneNumber ?? '');
    _notesController = TextEditingController(text: widget.contact?.notes ?? '');
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final XFile? pickedFile = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
    );

    if (pickedFile == null || !mounted) return;

    setState(() {
      _newImagePath = pickedFile.path;
    });
  }

  bool get _isFormValid =>
      _fullNameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty;

  static const _saveTimeout = Duration(seconds: 25);

  Future<bool?> _confirmDuplicate(ContactModel duplicate) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contact Already Exists'),
        content: Text(
          '${duplicate.fullName} already has this phone number saved. '
          'Save this as a new contact anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save Anyway'),
          ),
        ],
      ),
    );
  }

  /// The GPS/map capture step the auto-capture flow uses. Available to any
  /// contact, however it was saved. Both this and [_openEncounterDetails]
  /// write the contact themselves and land on its details, so this form has
  /// nothing to save afterwards.
  void _openLocationCapture() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaptureContextScreen(contactId: widget.contact!.id),
      ),
    );
  }

  /// The typed-in counterpart: place, address, coordinates, role, notes and
  /// the encounter date and time. Seeded with whatever the contact already
  /// has, since that screen saves every one of those fields.
  void _openEncounterDetails() {
    final contact = widget.contact!;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(
          contactId: contact.id,
          initialLat: contact.location?.lat,
          initialLng: contact.location?.lng,
          initialPlaceName: contact.location?.placeName,
          initialAddress: contact.location?.address,
          initialDateTime: contact.eventDate,
          initialRole: contact.role,
          initialNotes: contact.notes,
        ),
      ),
    );
  }

  Future<void> _onSubmit(ContactSaveFlow flow) async {
    if (!_isFormValid || _isSaving) return;
    setState(() {
      _inFlight = flow;
      _errorMessage = null;
    });

    final repository = ref.read(contactRepositoryProvider);
    final fullName = _fullNameController.text.trim();
    final phoneNumber = _phoneController.text.trim();
    final notes = _notesController.text.trim();

    if (!_isEditing) {
      final duplicate = await repository.findByPhoneNumber(phoneNumber);
      if (duplicate != null) {
        if (!mounted) return;
        final shouldContinue = await _confirmDuplicate(duplicate);
        if (shouldContinue != true) {
          if (mounted) setState(() => _inFlight = null);
          return;
        }
      }
    }

    if (!mounted) return;
    AppLoading.show();
    try {
      if (_isEditing) {
        final contactId = widget.contact!.id;
        await repository
            .updateContact(contactId, {
              'fullName': fullName,
              'phoneNumber': phoneNumber,
              'notes': notes.isEmpty ? null : notes,
            })
            .timeout(_saveTimeout);
        // The core save already succeeded above — a photo upload failure
        // from here on is non-fatal and shouldn't block/misreport the save.
        await _tryUploadPhoto(repository, contactId);
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      final contactId = await repository
          .createContact(
            ContactModel(
              id: '',
              fullName: fullName,
              phoneNumber: phoneNumber,
              notes: notes.isEmpty ? null : notes,
              source: ContactSource.manual,
              // Records which button was tapped, which is what sorts the
              // contact into the Captured or Manual tab. It does not restrict
              // the contact: either kind can gain a location, notes and
              // timeline entries afterwards.
              capturesContext: flow == ContactSaveFlow.captureContext,
            ),
          )
          .timeout(_saveTimeout);

      await _tryUploadPhoto(repository, contactId);

      if (!mounted) return;
      setState(() => _inFlight = null);

      if (flow == ContactSaveFlow.captureContext) {
        continueContactCaptureFlow(context, ref, contactId);
        return;
      }

      // A plain "Save" ends on the new contact's details — no context
      // capture step. pushReplacement rather than push so Back from there
      // returns to wherever the user started, instead of to a filled-in
      // form for a contact that now already exists.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SavedContactDetailsScreen(contactId: contactId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inFlight = null;
        _errorMessage = e is TimeoutException
            ? 'This is taking too long. Check your connection and try again.'
            : 'Could not save this contact: $e';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage!)));
    } finally {
      AppLoading.dismiss();
    }
  }

  /// Uploads the picked photo if any, swallowing failures — the contact
  /// record has already been created/updated by this point, so a Storage
  /// problem shouldn't block the user or read as "contact wasn't saved".
  Future<void> _tryUploadPhoto(ContactRepository repository, String contactId) async {
    if (_newImagePath == null) return;
    try {
      await repository
          .uploadContactPhoto(contactId: contactId, file: File(_newImagePath!))
          .timeout(_saveTimeout);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contact saved, but the photo could not be uploaded: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingPhotoUrl = widget.contact?.photoUrl;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          _isEditing ? 'Edit Contact' : 'New Contact',
          style: const TextStyle(
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _pickProfileImage,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ContactAvatar(
                          diameter: 104,
                          photoUrl: existingPhotoUrl,
                          localFile: _newImagePath != null ? File(_newImagePath!) : null,
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: GestureDetector(
                            onTap: _pickProfileImage,
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
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Image.asset(
                                  AppImages.camera,
                                  fit: BoxFit.contain,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add Photo (optional)',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Full Name',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _fullNameController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Enter full name',
                      hintStyle: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        color: AppColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.white,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: AppColors.border,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: AppColors.primaryBlue,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(
                          AppImages.person,
                          width: 22,
                          height: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Phone Number',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Enter phone number',
                      hintStyle: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        color: AppColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.white,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: AppColors.border,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: AppColors.primaryBlue,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(
                          AppImages.callCalling,
                          width: 22,
                          height: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Notes',
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Enter notes',
                      hintStyle: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        color: AppColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.white,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.border,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.primaryBlue,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                    ),
                  ),
                  // Any contact can carry a location, a role and an encounter
                  // time, however it was saved — a manually saved one just
                  // starts without them.
                  if (_isEditing) ...[
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Encounter Details',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DetailActionRow(
                      icon: _capturedPlace != null
                          ? Icons.location_on_rounded
                          : Icons.my_location_rounded,
                      title: _capturedPlace ?? 'Capture location automatically',
                      subtitle: _capturedPlace != null
                          ? 'Recapture place and time from the map'
                          : 'Use the map and GPS to set place and time',
                      highlightTitle: _capturedPlace != null,
                      onTap: _openLocationCapture,
                    ),
                    const SizedBox(height: 8),
                    _DetailActionRow(
                      icon: Icons.edit_note_rounded,
                      title: 'Edit encounter details',
                      subtitle:
                          'Place, address, coordinates, role, date and time',
                      onTap: _openEncounterDetails,
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_isEditing)
                    SizedBox(
                      width: 260,
                      child: CustomButton(
                        label: 'Save Changes',
                        onPressed: _isFormValid && !_isSaving
                            ? () => _onSubmit(ContactSaveFlow.save)
                            : null,
                        isLoading: _isSaving,
                        height: 50,
                        fontSize: 14,
                      ),
                    )
                  else ...[
                    // The two ways to finish a new contact. Capture leads
                    // somewhere else, hence the arrow and the primary colour;
                    // a plain save is the quieter option.
                    CustomButton(
                      label: 'Capture Context Automatically',
                      onPressed: _isFormValid && !_isSaving
                          ? () => _onSubmit(ContactSaveFlow.captureContext)
                          : null,
                      isLoading: _inFlight == ContactSaveFlow.captureContext,
                      height: 50,
                      fontSize: 14,
                      icon: Icons.arrow_forward_rounded,
                      iconSize: 18,
                    ),
                    const SizedBox(height: 10),
                    CustomButton(
                      label: 'Save',
                      onPressed: _isFormValid && !_isSaving
                          ? () => _onSubmit(ContactSaveFlow.save)
                          : null,
                      isLoading: _inFlight == ContactSaveFlow.save,
                      height: 50,
                      fontSize: 14,
                      color: AppColors.lightBlueFill,
                      textColor: AppColors.primaryBlue,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tappable route into a contact's encounter details, on the edit form.
class _DetailActionRow extends StatelessWidget {
  const _DetailActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlightTitle = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// True when the title is the contact's own captured place rather than a
  /// prompt, so it reads as data instead of an invitation.
  final bool highlightTitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.mutedGray,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primaryBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 14,
                      fontWeight: highlightTitle
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
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
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
