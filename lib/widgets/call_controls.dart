import 'package:flutter/material.dart';

/// The round accept/decline/end button used across every call surface.
///
/// Extracted from `calling_screen.dart` so the cellular call screen and the
/// in-app VoIP call screens share one definition — a call button that looks
/// slightly different depending on which screen you reached is the kind of
/// inconsistency users read as a bug.
class CircleCallButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const CircleCallButton({
    super.key,
    required this.color,
    required this.icon,
    required this.onTap,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: size * 0.44),
        ),
      ),
    );
  }
}

/// Decline (left) and accept (right) circles that can be either tapped, or
/// dragged toward the center — like a real phone's incoming-call row — to
/// trigger the same action once dragged past [_triggerDistance].
class SwipeToAnswerRow extends StatefulWidget {
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const SwipeToAnswerRow({super.key, required this.onAccept, required this.onDecline});

  @override
  State<SwipeToAnswerRow> createState() => _SwipeToAnswerRowState();
}

class _SwipeToAnswerRowState extends State<SwipeToAnswerRow> {
  static const double _triggerDistance = 72;

  // Decline drags right (positive), accept drags left (negative) — both
  // toward the center "Swipe to Answer" label.
  double _declineDrag = 0;
  double _acceptDrag = 0;
  bool _declineTriggered = false;
  bool _acceptTriggered = false;

  void _onDeclineDragUpdate(DragUpdateDetails details) {
    if (widget.onDecline == null || _declineTriggered) return;
    setState(() {
      _declineDrag = (_declineDrag + details.delta.dx).clamp(0.0, _triggerDistance);
    });
    if (_declineDrag >= _triggerDistance) {
      _declineTriggered = true;
      widget.onDecline!();
    }
  }

  void _onDeclineDragEnd(DragEndDetails details) {
    if (_declineTriggered) return;
    setState(() => _declineDrag = 0);
  }

  void _onAcceptDragUpdate(DragUpdateDetails details) {
    if (widget.onAccept == null || _acceptTriggered) return;
    setState(() {
      _acceptDrag = (_acceptDrag + details.delta.dx).clamp(-_triggerDistance, 0.0);
    });
    if (_acceptDrag <= -_triggerDistance) {
      _acceptTriggered = true;
      widget.onAccept!();
    }
  }

  void _onAcceptDragEnd(DragEndDetails details) {
    if (_acceptTriggered) return;
    setState(() => _acceptDrag = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onHorizontalDragUpdate: _onDeclineDragUpdate,
          onHorizontalDragEnd: _onDeclineDragEnd,
          child: AnimatedContainer(
            duration: _declineDrag == 0
                ? const Duration(milliseconds: 200)
                : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_declineDrag, 0, 0),
            child: CircleCallButton(
              color: Colors.red,
              icon: Icons.call_end,
              onTap: widget.onDecline,
            ),
          ),
        ),
        const Text(
          'Swipe to Answer',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        GestureDetector(
          onHorizontalDragUpdate: _onAcceptDragUpdate,
          onHorizontalDragEnd: _onAcceptDragEnd,
          child: AnimatedContainer(
            duration: _acceptDrag == 0
                ? const Duration(milliseconds: 200)
                : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_acceptDrag, 0, 0),
            child: CircleCallButton(
              color: Colors.green,
              icon: Icons.call,
              onTap: widget.onAccept,
            ),
          ),
        ),
      ],
    );
  }
}

/// The large circular caller avatar with an optional direction badge, shared
/// by the cellular and VoIP call screens.
class CallAvatar extends StatelessWidget {
  final ImageProvider? image;
  final Widget? badge;
  final Color backgroundColor;
  final double radius;

  const CallAvatar({
    super.key,
    required this.image,
    this.badge,
    this.backgroundColor = const Color(0xFFE0E0E0),
    this.radius = 70,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          backgroundImage: image,
          child: image == null
              ? Icon(Icons.person, size: radius, color: Colors.white)
              : null,
        ),
        if (badge != null)
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
              child: badge,
            ),
          ),
      ],
    );
  }
}

/// A labelled round toggle (Mute, Speaker) for the active-call screen.
class CallToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const CallToggleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.25),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 26,
                color: active ? Colors.black87 : Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
