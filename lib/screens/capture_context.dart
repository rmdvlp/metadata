import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' hide Location;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:metadata/core/loading/app_loading.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/contact_repository.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/app_back_button.dart';
import 'package:metadata/widgets/button.dart';
import 'package:metadata/screens/event_detail.dart';
import 'package:metadata/screens/saved_contact_details_screen.dart';

class CaptureContextScreen extends ConsumerStatefulWidget {
  const CaptureContextScreen({super.key, required this.contactId});

  final String contactId;

  @override
  ConsumerState<CaptureContextScreen> createState() =>
      _CaptureContextScreenState();
}

class _CaptureContextScreenState extends ConsumerState<CaptureContextScreen> {
  final MapController _mapController = MapController();
  final Location _location = Location();

  /// The moment this encounter was captured. Fixed when the screen opens
  /// rather than recomputed in build, so the date and time shown below are
  /// the exact values persisted on confirm.
  final DateTime _capturedAt = DateTime.now();
  LatLng _currentLocation = LatLng(28.6139, 77.2090);
  bool _isLoadingLocation = true;
  bool _isResolvingPlace = false;
  bool _isSaving = false;
  String? _placeName;
  String? _address;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
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
        final LatLng nextPoint = LatLng(latitude, longitude);
        setState(() {
          _currentLocation = nextPoint;
          _isLoadingLocation = false;
        });
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

    if (mounted) {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _onMapTapped(LatLng point) {
    setState(() => _currentLocation = point);
    try {
      _mapController.move(point, _mapController.camera.zoom);
    } catch (_) {
      // Ignore movement errors during very early map lifecycle.
    }
    unawaited(_reverseGeocode(point));
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _isResolvingPlace = true);
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
        _placeName = (name != null && name.isNotEmpty) ? name : null;
        _address = address.isNotEmpty ? address : null;
      });
    } catch (_) {
      // Non-fatal: user can still save with just lat/lng if reverse
      // geocoding fails (e.g. no network, or nothing found at this point).
    } finally {
      if (mounted) setState(() => _isResolvingPlace = false);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _confirmContext() async {
    setState(() => _isSaving = true);
    AppLoading.show();
    try {
      await ref
          .read(contactRepositoryProvider)
          .updateContact(widget.contactId, {
            'location': ContactLocation(
              lat: _currentLocation.latitude,
              lng: _currentLocation.longitude,
              placeName: _placeName,
              address: _address,
            ).toMap(),
            // Without this the contact keeps a location but no encounter
            // time, so Contact Details renders Date and Time as "—" even
            // though this screen just displayed them.
            'eventDate': Timestamp.fromDate(_capturedAt),
          })
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      // Per the design, "Confirm Context" should land directly on Contact
      // Details — the Edit screen is only for the explicit "Edit Detail" /
      // pencil actions elsewhere on this screen.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SavedContactDetailsScreen(contactId: widget.contactId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save this location: $e')),
      );
    } finally {
      AppLoading.dismiss();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = _capturedAt;
    final String currentDate =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final String currentTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          'Capture Context',
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: 260,
                      child: _isLoadingLocation
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryBlue,
                              ),
                            )
                          : Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter: _currentLocation,
                                    initialZoom: 15,
                                    onTap: (tapPosition, point) => _onMapTapped(point),
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
                                if (_isResolvingPlace)
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: AppColors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: AppColors.primaryBlue,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap anywhere on the map to set this contact\'s location',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Place Detected',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _placeName ?? 'Place Name',
                                    style: const TextStyle(
                                      fontFamily: 'SF Pro Display',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Image.asset(
                                        AppImages.location,
                                        width: 18,
                                        height: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _address ?? 'Tap the map to detect an address',
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
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EventDetailScreen(
                                      contactId: widget.contactId,
                                      initialLat: _currentLocation.latitude,
                                      initialLng: _currentLocation.longitude,
                                      initialPlaceName: _placeName,
                                      initialAddress: _address,
                                      initialDateTime: DateTime.now(),
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Image.asset(
                                  AppImages.edit2,
                                  width: 22,
                                  height: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
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
                              '${_currentLocation.longitude.toStringAsFixed(4)}° E',
                              style: const TextStyle(
                                fontFamily: 'SF Pro Display',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 1,
                              height: 14,
                              color: AppColors.border,
                            ),
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
                              '${_currentLocation.latitude.toStringAsFixed(4)}° N',
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
                              value: currentDate,
                            ),
                            const SizedBox(width: 24),
                            _InfoIconBlock(
                              icon: Icons.access_time_rounded,
                              label: 'Time',
                              value: currentTime,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            CustomButton(
                              label: 'Confirm Context',
                              onPressed: _isSaving ? null : _confirmContext,
                              isLoading: _isSaving,
                              height: 50,
                              fontSize: 13,
                            ),
                            const SizedBox(height: 12),
                            CustomButton(
                              label: 'Edit Detail',
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EventDetailScreen(
                                      contactId: widget.contactId,
                                      initialLat: _currentLocation.latitude,
                                      initialLng: _currentLocation.longitude,
                                      initialPlaceName: _placeName,
                                      initialAddress: _address,
                                      initialDateTime: DateTime.now(),
                                    ),
                                  ),
                                );
                              },
                              height: 50,
                              fontSize: 13,
                              color: AppColors.lightBlueFill,
                              textColor: AppColors.primaryBlue,
                            ),
                          ],
                        ),
                      ],
                    ),
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
