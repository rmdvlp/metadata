import 'dart:async';

import 'package:flutter/material.dart';
import 'package:metadata/models/encounter_details.dart';
import 'package:metadata/models/timeline_entry.dart';
import 'package:metadata/screens/bank_chat_screen.dart';
import 'package:metadata/utils/app_images.dart';
import 'package:metadata/widgets/call_controls.dart';

/// ---------------------------------------------------------------------------
/// PUBLIC ENTRY WIDGET
/// ---------------------------------------------------------------------------
///
/// Use `isIncoming: true` for the ringing / "Swipe to Answer" screen
/// (first mock), and `isIncoming: false` for the connected call screen
/// where the top area becomes the live-call surface (second mock).
///
/// Both variants share the same animated bottom "shutter" sheet that
/// slides up from the bottom half of the screen when the chevron button
/// is tapped, and slides back down when tapped again.
class CallingScreen extends StatelessWidget {
  final String callerName;
  final String phoneNumber;
  final ImageProvider? avatarImage;
  final bool isIncoming;
  // Only meaningful when isIncoming is false: true once the call is
  // actually live (shows a running duration), false while still dialing out
  // (shows "Calling…"). Defaults true so the existing incoming-accepted
  // flow (already live by the time it swaps to this variant) needs no
  // change.
  final bool isConnected;

  /// When the call went live. The duration counts up from this rather than
  /// from when this screen was built, so it stays honest across the screen
  /// being rebuilt or replaced mid-call — and so it reads as the real talk
  /// time, which is the number that gets written to the call log.
  ///
  /// Null falls back to "started now", which is what a caller that has no
  /// connect time of its own to hand over means.
  final DateTime? connectedAt;
  final EncounterDetails encounterDetails;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onAddNewTimelineEntry;
  final VoidCallback? onEditEncounter;

  const CallingScreen({
    super.key,
    required this.callerName,
    required this.phoneNumber,
    required this.encounterDetails,
    this.avatarImage,
    this.isIncoming = true,
    this.isConnected = true,
    this.connectedAt,
    this.onAccept,
    this.onDecline,
    this.onAddNewTimelineEntry,
    this.onEditEncounter,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isIncoming ? Colors.white : const Color(0xFFBDBDBD),
      body: SafeArea(
        bottom: false,
        child: _CallScreenBody(
          callerName: callerName,
          phoneNumber: phoneNumber,
          avatarImage: avatarImage,
          isIncoming: isIncoming,
          isConnected: isConnected,
          connectedAt: connectedAt,
          encounterDetails: encounterDetails,
          onAccept: onAccept,
          onDecline: onDecline,
          onAddNewTimelineEntry: onAddNewTimelineEntry,
          onEditEncounter: onEditEncounter,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// BODY (stateful — owns the expand/collapse animation of the shutter)
/// ---------------------------------------------------------------------------

class _CallScreenBody extends StatefulWidget {
  final String callerName;
  final String phoneNumber;
  final ImageProvider? avatarImage;
  final bool isIncoming;
  final bool isConnected;
  final DateTime? connectedAt;
  final EncounterDetails encounterDetails;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onAddNewTimelineEntry;
  final VoidCallback? onEditEncounter;

  const _CallScreenBody({
    required this.callerName,
    required this.phoneNumber,
    required this.avatarImage,
    required this.isIncoming,
    required this.isConnected,
    required this.connectedAt,
    required this.encounterDetails,
    required this.onAccept,
    required this.onDecline,
    required this.onAddNewTimelineEntry,
    required this.onEditEncounter,
  });

  @override
  State<_CallScreenBody> createState() => _CallScreenBodyState();
}

class _CallScreenBodyState extends State<_CallScreenBody> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Collapsed = smaller to show buttons. Expanded = most of the screen,
    // leaving a strip at the top (matches the two mocks).
    final collapsedHeight = screenHeight * 0.38;
    final expandedHeight = screenHeight * 0.85;

    return Stack(
      children: [
        // ---------------- top call surface ----------------
        Positioned.fill(
          child: widget.isIncoming
              ? _IncomingCallTop(
                  callerName: widget.callerName,
                  phoneNumber: widget.phoneNumber,
                  avatarImage: widget.avatarImage,
                  onAccept: widget.onAccept,
                  onDecline: widget.onDecline,
                )
              : _LiveCallTop(
                  callerName: widget.callerName,
                  phoneNumber: widget.phoneNumber,
                  avatarImage: widget.avatarImage,
                  isConnected: widget.isConnected,
                  connectedAt: widget.connectedAt,
                  onEndCall: widget.onDecline,
                ),
        ),

        // ---------------- bottom shutter sheet ----------------
        AnimatedPositioned(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          bottom: 0,
          height: _expanded ? expandedHeight : collapsedHeight,
          child: _EncounterSheet(
            expanded: _expanded,
            onToggle: _toggle,
            details: widget.encounterDetails,
            onAddNewTimelineEntry: widget.onAddNewTimelineEntry,
            onEditEncounter: widget.onEditEncounter,
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// INCOMING CALL TOP (avatar, name, swipe-to-answer row)
/// ---------------------------------------------------------------------------

class _IncomingCallTop extends StatelessWidget {
  final String callerName;
  final String phoneNumber;
  final ImageProvider? avatarImage;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const _IncomingCallTop({
    required this.callerName,
    required this.phoneNumber,
    required this.avatarImage,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const Text(
            'In Coming Call',
            style: TextStyle(
              fontSize: 22,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 40),
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 70,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: avatarImage,
                child: avatarImage == null
                    ? const Icon(Icons.person, size: 70, color: Colors.white)
                    : null,
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    AppImages.callIncoming,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            callerName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            phoneNumber,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 36),
          SwipeToAnswerRow(onAccept: onAccept, onDecline: onDecline),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// LIVE CALL TOP (outgoing "Calling…" / connected — avatar, name, duration,
/// end call)
/// ---------------------------------------------------------------------------
///
/// Shown whenever `isIncoming: false` — both right after placing an outgoing
/// call (isConnected: false, shows "Calling…") and once it's actually live,
/// whether reached by placing a call that connects or by accepting an
/// incoming one (isConnected: true, shows a running duration timer).
class _LiveCallTop extends StatefulWidget {
  final String callerName;
  final String phoneNumber;
  final ImageProvider? avatarImage;
  final bool isConnected;
  final DateTime? connectedAt;
  final VoidCallback? onEndCall;

  const _LiveCallTop({
    required this.callerName,
    required this.phoneNumber,
    required this.avatarImage,
    required this.isConnected,
    required this.connectedAt,
    required this.onEndCall,
  });

  @override
  State<_LiveCallTop> createState() => _LiveCallTopState();
}

class _LiveCallTopState extends State<_LiveCallTop> {
  Timer? _timer;

  /// Fallback start for a caller that handed over no connect time of its own.
  /// Held in state rather than recomputed, so the count doesn't reset itself on
  /// every rebuild.
  DateTime? _fallbackStart;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _LiveCallTop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected != oldWidget.isConnected ||
        widget.connectedAt != oldWidget.connectedAt) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.isConnected) {
      _fallbackStart = null;
      return;
    }
    _fallbackStart = widget.connectedAt == null ? DateTime.now() : null;
    // The count is derived from the connect time on every tick rather than
    // incremented, so it can't drift away from the real talk time when ticks
    // are delayed (which is normal for a backgrounded app) — the number on
    // screen matches the duration the call log ends up with.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _statusText {
    if (!widget.isConnected) return 'Calling…';
    final start = widget.connectedAt ?? _fallbackStart;
    final elapsed = start == null
        ? Duration.zero
        : DateTime.now().difference(start);
    final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
    final hours = seconds ~/ 3600;
    final minutePart = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final secondPart = (seconds % 60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:$minutePart:$secondPart'
        : '$minutePart:$secondPart';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 56),
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 70,
                backgroundColor: Colors.grey.shade400,
                backgroundImage: widget.avatarImage,
                child: widget.avatarImage == null
                    ? const Icon(Icons.person, size: 70, color: Colors.white)
                    : null,
              ),
              // Only meaningful while still dialing out — once connected this
              // screen is also reused for an accepted incoming call, so a
              // direction badge would be wrong for that case.
              if (!widget.isConnected)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(
                      AppImages.callOutgoing,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            widget.callerName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _statusText,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 40),
          CircleCallButton(
            color: Colors.red,
            icon: Icons.call_end,
            onTap: widget.onEndCall,
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// ENCOUNTER DETAILS SHUTTER SHEET
/// ---------------------------------------------------------------------------

class _EncounterSheet extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final EncounterDetails details;
  final VoidCallback? onAddNewTimelineEntry;
  final VoidCallback? onEditEncounter;

  const _EncounterSheet({
    required this.expanded,
    required this.onToggle,
    required this.details,
    required this.onAddNewTimelineEntry,
    required this.onEditEncounter,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF5F5F5),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Encounter Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PlaceCard(details: details, onEdit: onEditEncounter),
                          const SizedBox(height: 14),
                          const Text(
                            'Note',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _NoteBox(note: details.note),
                          // Below Notes, same as on the saved-contact screen.
                          // Present while the phone is ringing on purpose:
                          // this is the moment the caller reads out where to
                          // pay, and copying beats writing it down.
                          if (details.contactId.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            BankChatButton(
                              contactId: details.contactId,
                              contactName: details.contactName,
                              compact: true,
                            ),
                          ],
                          // Timeline only shown once the sheet is expanded,
                          // matching the second mock.
                          if (expanded) ...[
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Timeline',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: onAddNewTimelineEntry,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add New'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _TimelineList(entries: details.timeline),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ---- chevron toggle button, straddling the top edge of the sheet ----
        Positioned(
          top: -16,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: Colors.blue,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                onTap: onToggle,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: Icon(
                    expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Card with place name / address / lat-long / date & time.
class _PlaceCard extends StatelessWidget {
  final EncounterDetails details;
  final VoidCallback? onEdit;

  const _PlaceCard({required this.details, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  details.placeName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              InkWell(
                onTap: onEdit,
                child: const Icon(Icons.edit, size: 18, color: Colors.blue),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  details.address,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _LabelValue(label: 'Longitude:', value: details.longitude),
              const SizedBox(width: 8),
              Container(width: 1, height: 14, color: Colors.grey.shade300),
              const SizedBox(width: 8),
              _LabelValue(label: 'Latitude:', value: details.latitude),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _IconLabelValue(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: details.date,
                ),
              ),
              Expanded(
                child: _IconLabelValue(
                  icon: Icons.access_time,
                  label: 'Time',
                  value: details.time,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;

  const _LabelValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: Colors.black87),
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _IconLabelValue extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _IconLabelValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blue),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoteBox extends StatelessWidget {
  final String note;

  const _NoteBox({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        note,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      ),
    );
  }
}

class _TimelineList extends StatelessWidget {
  final List<TimelineEntry> entries;

  const _TimelineList({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < entries.length; i++)
          _TimelineTile(entry: entries[i], isLast: i == entries.length - 1),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final TimelineEntry entry;
  final bool isLast;

  const _TimelineTile({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: Colors.grey.shade300),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    entry.displayDate,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
