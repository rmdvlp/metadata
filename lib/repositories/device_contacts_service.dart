import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/models/contact_model.dart';
import 'package:metadata/repositories/contact_repository.dart';

final deviceContactsServiceProvider = Provider<DeviceContactsService>((ref) {
  return DeviceContactsService(
    contactRepository: ref.watch(contactRepositoryProvider),
  );
});

/// Wraps `flutter_contacts` (device address book) + syncs into Firestore
/// under the signed-in user via [ContactRepository].
class DeviceContactsService {
  DeviceContactsService({required ContactRepository contactRepository})
    : _contactRepository = contactRepository;

  final ContactRepository _contactRepository;

  Future<bool> hasPermission() => FlutterContacts.permissions.has(PermissionType.read);

  Future<bool> requestPermission() async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    return status == PermissionStatus.granted || status == PermissionStatus.limited;
  }

  Future<List<Contact>> fetchDeviceContacts() {
    return FlutterContacts.getAll(
      properties: {ContactProperty.phone, ContactProperty.photoThumbnail},
    );
  }

  /// Fetches device contacts and creates any that aren't already synced.
  /// Returns the number of newly-synced contacts.
  Future<int> syncDeviceContactsToFirestore() async {
    if (!await hasPermission()) return 0;

    final deviceContacts = await fetchDeviceContacts();
    final alreadySynced = await _contactRepository.getDeviceContactIds();

    var synced = 0;
    for (final contact in deviceContacts) {
      final deviceId = contact.id;
      if (deviceId == null || alreadySynced.contains(deviceId)) continue;
      if (contact.phones.isEmpty) continue;

      final contactId = await _contactRepository.createContact(
        ContactModel(
          id: '',
          fullName: contact.displayName?.isNotEmpty == true
              ? contact.displayName!
              : contact.phones.first.number,
          phoneNumber: contact.phones.first.number,
          source: ContactSource.device,
          deviceContactId: deviceId,
        ),
      );

      final thumbnail = contact.photo?.thumbnail;
      if (thumbnail != null && thumbnail.isNotEmpty) {
        try {
          await _contactRepository.uploadContactPhotoBytes(
            contactId: contactId,
            bytes: thumbnail,
          );
        } catch (_) {
          // Non-fatal: the contact itself is already saved. A transient
          // network/Storage failure here shouldn't abort syncing the rest
          // of the device contacts (it previously did, since this was
          // unguarded and threw out of the loop).
        }
      }

      synced++;
    }

    return synced;
  }
}
