import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:metadata/utils/date_formatting.dart';

/// One row in a contact's "Timeline" section (e.g. FIRST MET / COFFEE CHAT).
class TimelineEntry {
  final String id;
  final String label;
  final String title;
  final String subtitle;
  final DateTime date;
  final DateTime? createdAt;
  final double? lat;
  final double? lng;
  final String? role;

  const TimelineEntry({
    required this.id,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.date,
    this.createdAt,
    this.lat,
    this.lng,
    this.role,
  });

  String get displayDate => formatShortDate(date);

  factory TimelineEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return TimelineEntry(
      id: doc.id,
      label: data['label'] as String? ?? '',
      title: data['title'] as String? ?? '',
      subtitle: data['subtitle'] as String? ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      role: data['role'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'label': label,
    'title': title,
    'subtitle': subtitle,
    'date': Timestamp.fromDate(date),
    'createdAt': FieldValue.serverTimestamp(),
    'lat': lat,
    'lng': lng,
    'role': role,
  };

  Map<String, dynamic> toUpdateMap() => {
    'label': label,
    'title': title,
    'subtitle': subtitle,
    'date': Timestamp.fromDate(date),
    'lat': lat,
    'lng': lng,
    'role': role,
  };
}
