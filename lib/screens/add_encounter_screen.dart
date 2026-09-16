import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' hide Location;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/timeline_entry.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/date_formatting.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';

/// Dedicated full-screen "Add Encounter" flow for a new Timeline entry —
/// replaces the old plain popup dialog so users get the same map +
/// place/address/role/date-time capture used elsewhere in the app.
/// Pass [existing] to edit an entry already on the timeline instead of
/// creating a new one.
class AddEncounterScreen extends ConsumerStatefulWidget {
  const AddEncounterScreen({super.key, required this.contactId, this.existing});

  final String contactId;
  final TimelineEntry? existing;

  @override
  ConsumerState<AddEncounterScreen> createState() => _AddEncounterScreenState();
}

class _AddEncounterScreenState extends ConsumerState<AddEncounterScreen> {
  final MapController _mapController = MapController();
  final Location _location = Location();

  late final TextEditingController _placeNameController;
  late final TextEditingController _addressController;
  late final TextEditingController _lonController;
  late final TextEditingController _latController;
  late final TextEditingController _roleController;

  late LatLng _currentLocation;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  bool get _isEditing => widget.existing != null;
  bool _isLoadingLocation = true;
  bool _isGpsVerified = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _currentLocation = LatLng(existing?.lat ?? 28.6139, existing?.lng ?? 77.2090);
    _placeNameController = TextEditingController(text: existing?.title ?? '');
    _addressController = TextEditingController(text: existing?.subtitle ?? '');
    _lonController = TextEditingController(
      text: existing?.lng != null ? existing!.lng!.toStringAsFixed(4) : '',
    );
    _latController = TextEditingController(
      text: existing?.lat != null ? existing!.lat!.toStringAsFixed(4) : '',
    );
    _roleController = TextEditingController(text: existing?.role ?? '');
    _selectedDate = existing?.date ?? DateTime.now();
    _selectedTime = TimeOfDay.fromDateTime(existing?.date ?? DateTime.now());

    if (_isEditing) {
      _isLoadingLocation = false;
      _isGpsVerified = existing?.lat != null;
    } else {
      _initializeLocation();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _placeNameController.dispose();
    _addressController.dispose();
    _lonController.dispose();
    _latController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    final bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      await _location.requestService();
    }

    PermissionStatus permissionStatus = await _location.hasPermission();
    if (permissionStatus == PermissionStatus.denied) {
      permissionStatus = await _location.requestPermission();
    }

    if (permissionStatus == PermissionStatus.granted ||
        permissionStatus == PermissionStatus.grantedLimited) {
      final LocationData locationData = await _location.getLocation();
      final double? latitude = locationData.latitude;
      final double? longitude = locationData.longitude;

      if (latitude != null && longitude != null && mounted) {
        final nextPoint = LatLng(latitude, longitude);
        _applyPoint(nextPoint, verified: true);
        setState(() => _isLoadingLocation = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            _mapController.move(nextPoint, 15);
          } catch (_) {
            // Ignore movement errors during very early map lifecycle.
          }
        });
        unawaited(_reverseGeocode(nextPoint));
        return;
      }
    }

    if (mounted) setState(() => _isLoadingLocation = false);
  }

  void _applyPoint(LatLng point, {bool verified = false}) {
    _currentLocation = point;
    _lonController.text = point.longitude.toStringAsFixed(4);
    _latController.text = point.latitude.toStringAsFixed(4);
    if (verified) _isGpsVerified = true;
  }

  void _onMapTapped(LatLng point) {
    setState(() => _applyPoint(point));
    try {
      _mapController.move(point, _mapController.camera.zoom);
    } catch (_) {
      // Ignore movement errors during very early map lifecycle.
    }
    unawaited(_reverseGeocode(point));
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
      // Non-fatal: user can still save with just lat/lng, or edit the
      // place name/address fields manually if reverse geocoding fails.
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _selectedTime);
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    final placeName = _placeNameController.text.trim();
    if (placeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a place name.')),
      );
      return;
    }
    final role = _roleController.text.trim();
    if (role.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a role.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    AppLoading.show();
    try {
      final date = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final lat = double.tryParse(_latController.text.trim());
      final lng = double.tryParse(_lonController.text.trim());

      final entry = TimelineEntry(
        id: widget.existing?.id ?? '',
        label: role.toUpperCase(),
        title: placeName,
        subtitle: _addressController.text.trim(),
        date: date,
        lat: lat,
        lng: lng,
        role: role,
      );

      final repository = ref.read(contactRepositoryProvider);
      if (_isEditing) {
        await repository.updateTimelineEntry(widget.contactId, entry).timeout(
          const Duration(seconds: 20),
        );
      } else {
        await repository.addTimelineEntry(widget.contactId, entry).timeout(
          const Duration(seconds: 20),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save this encounter: $e')),
      );
    } finally {
      AppLoading.dismiss();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _isEditing ? 'Edit Encounter' : 'Add Encounter',
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 96,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _isLoadingLocation
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryBlue,
                                ),
                              )
                            : FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _currentLocation,
                                  initialZoom: 15,
                                  onTap: (tapPosition, point) =>
                                      _onMapTapped(point),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.example.metadata',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: _currentLocation,
                                        width: 40,
                                        height: 40,
                                        child: const Icon(
                                          Icons.location_on,
                                          color: AppColors.primaryBlue,
                                          size: 34,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                      // Sits on the map rather than under it: the status is
                      // about the pin, and a separate row cost a line the
                      // screen cannot spare.
                      if (!_isLoadingLocation)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _GpsChip(verified: _isGpsVerified),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _FieldLabel('Place name'),
              _FormField(controller: _placeNameController, hint: 'e.g. Blue Bottle Coffee'),
              const SizedBox(height: 8),
              _FieldLabel('Address'),
              _FormField(controller: _addressController, hint: 'Street, city'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel('Longitude (Optional)'),
                        _FormField(
                          controller: _lonController,
                          hint: '—',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel('Latitude (Optional)'),
                        _FormField(
                          controller: _latController,
                          hint: '—',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _FieldLabel('Role'),
              _FormField(controller: _roleController, hint: 'e.g. Important'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel('Date'),
                        _PickerField(
                          value: formatShortDate(_selectedDate),
                          icon: Icons.calendar_today_rounded,
                          onTap: _pickDate,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel('Time'),
                        _PickerField(
                          value: formatTime(
                            DateTime(2000, 1, 1, _selectedTime.hour, _selectedTime.minute),
                          ),
                          icon: Icons.access_time_rounded,
                          onTap: _pickTime,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      label: 'Discard',
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      color: Colors.white,
                      textColor: AppColors.textPrimary,
                      height: 50,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomButton(
                      label: 'Save',
                      onPressed: _isSaving ? null : _onSave,
                      isLoading: _isSaving,
                      height: 50,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "GPS verified" / "Tap the map to set a location", as a pill over the map.
class _GpsChip extends StatelessWidget {
  const _GpsChip({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.gps_not_fixed_rounded,
            size: 13,
            color: verified ? Colors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            verified ? 'GPS verified' : 'Tap the map to set a location',
            style: const TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({required this.controller, required this.hint, this.keyboardType});

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'SF Pro Display', fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'SF Pro Display', color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.mutedGray,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.value, required this.icon, required this.onTap});

  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.mutedGray,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontFamily: 'SF Pro Display', fontSize: 14),
              ),
            ),
            Icon(icon, size: 16, color: AppColors.primaryBlue),
          ],
        ),
      ),
    );
  }
}
