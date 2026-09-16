import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.contactId,
    this.initialLat,
    this.initialLng,
    this.initialPlaceName,
    this.initialAddress,
    this.initialDateTime,
    this.initialRole,
    this.initialNotes,
  });

  final String contactId;
  final double? initialLat;
  final double? initialLng;
  final String? initialPlaceName;
  final String? initialAddress;
  final DateTime? initialDateTime;

  /// Seeded when editing a contact that already has these. Saving writes both
  /// fields unconditionally, so starting them blank for an existing contact
  /// would wipe whatever it had.
  final String? initialRole;
  final String? initialNotes;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  final MapController _mapController = MapController();
  late final TextEditingController _placeNameController = TextEditingController(
    text: widget.initialPlaceName ?? '',
  );
  late final TextEditingController _addressController = TextEditingController(
    text: widget.initialAddress ?? '',
  );
  late final TextEditingController _latitudeController = TextEditingController(
    text: widget.initialLat?.toStringAsFixed(4) ?? '',
  );
  late final TextEditingController _longitudeController = TextEditingController(
    text: widget.initialLng?.toStringAsFixed(4) ?? '',
  );
  late final TextEditingController _roleController = TextEditingController(
    text: widget.initialRole ?? '',
  );
  late final TextEditingController _notesController = TextEditingController(
    text: widget.initialNotes ?? '',
  );
  /// Where the pin is. The single source of truth for the map, kept in step
  /// with the latitude/longitude fields in both directions.
  late LatLng _point = LatLng(
    widget.initialLat ?? 28.6139,
    widget.initialLng ?? 77.2090,
  );
  late DateTime _capturedAt = widget.initialDateTime ?? DateTime.now();
  bool _isSaving = false;
  bool _isDiscarding = false;

  @override
  void dispose() {
    _placeNameController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _roleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  LatLng _mapCenter() => _point;

  /// Tapping the map drops the pin there, fills in the coordinates, and looks
  /// up the place name and address for that spot.
  void _onMapTapped(LatLng point) {
    setState(() {
      _point = point;
      _latitudeController.text = point.latitude.toStringAsFixed(4);
      _longitudeController.text = point.longitude.toStringAsFixed(4);
    });
    _moveCamera(point);
    unawaited(_reverseGeocode(point));
  }

  /// The other direction: typing coordinates moves the pin to match.
  void _onCoordinateTyped() {
    final lat = double.tryParse(_latitudeController.text.trim());
    final lng = double.tryParse(_longitudeController.text.trim());
    if (lat == null || lng == null) return;
    if (lat.abs() > 90 || lng.abs() > 180) return;
    final point = LatLng(lat, lng);
    setState(() => _point = point);
    _moveCamera(point);
  }

  void _moveCamera(LatLng point) {
    try {
      _mapController.move(point, _mapController.camera.zoom);
    } catch (_) {
      // Ignore movement errors during very early map lifecycle.
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final placemarks = await Geocoding()
          .placemarkFromCoordinates(point.latitude, point.longitude)
          .timeout(const Duration(seconds: 12));

      if (!mounted || placemarks.isEmpty) return;
      final place = placemarks.first;

      final name = <String?>[place.name, place.subLocality, place.locality]
          .whereType<String>()
          .where((s) => s.isNotEmpty && s != place.street)
          .firstOrNull;
      final address = <String?>[
        place.street,
        place.locality,
        place.administrativeArea,
        place.country,
      ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

      setState(() {
        if (name != null && name.isNotEmpty) _placeNameController.text = name;
        if (address.isNotEmpty) _addressController.text = address;
      });
    } catch (_) {
      // Non-fatal: the coordinates are already set, and both text fields stay
      // editable by hand if the lookup fails (offline, nothing at this point).
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _capturedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _capturedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _capturedAt.hour,
        _capturedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_capturedAt),
    );
    if (picked == null) return;
    setState(() {
      _capturedAt = DateTime(
        _capturedAt.year,
        _capturedAt.month,
        _capturedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _onSave() async {
    if (_isSaving || _isDiscarding) return;
    final role = _roleController.text.trim();
    if (role.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a role.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    AppLoading.show();

    final lat = double.tryParse(_latitudeController.text) ?? _mapCenter().latitude;
    final lng = double.tryParse(_longitudeController.text) ?? _mapCenter().longitude;

    try {
      await ref
          .read(contactRepositoryProvider)
          .updateContact(widget.contactId, {
            'location': ContactLocation(
              lat: lat,
              lng: lng,
              placeName: _placeNameController.text.trim().isEmpty
                  ? null
                  : _placeNameController.text.trim(),
              address: _addressController.text.trim().isEmpty
                  ? null
                  : _addressController.text.trim(),
            ).toMap(),
            'role': role,
            'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            'eventDate': Timestamp.fromDate(_capturedAt),
          })
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SavedContactDetailsScreen(contactId: widget.contactId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save these details: $e')),
      );
    } finally {
      AppLoading.dismiss();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onDiscard() async {
    if (_isSaving || _isDiscarding) return;
    setState(() => _isDiscarding = true);
    AppLoading.show();

    try {
      await ref
          .read(contactRepositoryProvider)
          .deleteContact(widget.contactId)
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not discard this contact: $e')),
      );
    } finally {
      AppLoading.dismiss();
      if (mounted) setState(() => _isDiscarding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentDate =
        '${_capturedAt.day.toString().padLeft(2, '0')}/${_capturedAt.month.toString().padLeft(2, '0')}/${_capturedAt.year}';
    final String currentTime =
        '${_capturedAt.hour.toString().padLeft(2, '0')}:${_capturedAt.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Edit Details',
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MapPreview(
                    mapController: _mapController,
                    center: _mapCenter(),
                    onTap: _onMapTapped,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tap the map to move the pin',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _LabeledTextField(
                    label: 'Place name',
                    controller: _placeNameController,
                    hintText: 'Place name',
                    trailingIcon: AppImages.location,
                  ),
                  const SizedBox(height: 12),
                  _LabeledTextField(
                    label: 'Address',
                    controller: _addressController,
                    hintText: 'Address',
                    trailingIcon: AppImages.location,
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _LabeledTextField(
                          label: 'Latitude',
                          controller: _latitudeController,
                          hintText: '31.5204',
                          labelFontSize: 12,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          onChanged: (_) => _onCoordinateTyped(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _LabeledTextField(
                          label: 'Longitude',
                          controller: _longitudeController,
                          hintText: '74.3587',
                          labelFontSize: 12,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          onChanged: (_) => _onCoordinateTyped(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _LabeledTextField(
                    label: 'Role',
                    controller: _roleController,
                    hintText: 'e.g. Client, Mentor',
                    trailingIcon: AppImages.person,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StaticInfoChip(
                          label: 'Date',
                          value: currentDate,
                          icon: AppImages.calendar2,
                          onTap: _pickDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StaticInfoChip(
                          label: 'Time',
                          value: currentTime,
                          icon: AppImages.clock,
                          onTap: _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _LabeledTextField(
                    label: 'Notes',
                    controller: _notesController,
                    hintText: 'Notes',
                    minLines: 3,
                    maxLines: 6,
                  ),
                  const SizedBox(height: 20),
                  Column(
                    children: [
                      CustomButton(
                        label: 'Save',
                        onPressed: _isSaving || _isDiscarding ? null : _onSave,
                        isLoading: _isSaving,
                      ),
                      const SizedBox(height: 12),
                      CustomButton(
                        label: 'Discard',
                        onPressed: _isSaving || _isDiscarding ? null : _onDiscard,
                        isLoading: _isDiscarding,
                        color: Colors.white,
                        textColor: AppColors.textPrimary,
                        fontSize: 16,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded map preview shown at the top of the screen.
class _MapPreview extends StatelessWidget {
  const _MapPreview({
    required this.mapController,
    required this.center,
    required this.onTap,
  });

  final MapController mapController;
  final LatLng center;
  final void Function(LatLng point) onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 200,
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            onTap: (tapPosition, point) => onTap(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.metadata',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 44,
                  height: 44,
                  child: const Icon(
                    Icons.location_on,
                    color: AppColors.primaryBlue,
                    size: 38,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A labeled input field with a muted-gray background, used for every
/// editable field on this screen (place name, address, lat/lng, role, notes).
class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.trailingIcon,
    this.minLines = 1,
    this.maxLines = 1,
    this.labelFontSize = 14,
    this.keyboardType,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final String? trailingIcon;
  final int minLines;
  final int maxLines;
  final double labelFontSize;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: labelFontSize,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.mutedGray,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Row(
            crossAxisAlignment: maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  minLines: minLines,
                  maxLines: maxLines,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                    // Force the field's own background to match the
                    // surrounding container instead of the theme default
                    // (white), which is what was showing through before.
                    filled: true,
                    fillColor: AppColors.mutedGray,
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 10),
                Image.asset(trailingIcon!, width: 18, height: 18),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A read-only chip used for the Date / Time display row.
/// Date/Time chip. Tappable when [onTap] is given, which is how the encounter
/// date and time are changed.
class _StaticInfoChip extends StatelessWidget {
  const _StaticInfoChip({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.mutedGray,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Image.asset(icon, width: 18, height: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
