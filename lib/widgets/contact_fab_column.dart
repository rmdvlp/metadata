import 'package:flutter/material.dart';
import 'package:metadata/screens/contact_screen.dart';
import 'package:metadata/screens/dialer_screen.dart';
import 'package:metadata/utils/app_colors.dart';

/// Shared "dial a number" + "add a new contact" floating action buttons —
/// used on both Home and the Saved Contacts screen so every contacts list
/// offers the same quick actions without duplicating the wiring.
class ContactFabColumn extends StatelessWidget {
  const ContactFabColumn({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'dialerFab',
          shape: const CircleBorder(),
          onPressed: () => showDialerSheet(context),
          backgroundColor: AppColors.mutedGray,
          foregroundColor: AppColors.primaryBlue,
          elevation: 1,
          child: const Icon(Icons.dialpad_rounded, size: 24),
        ),
        const SizedBox(height: 14),
        FloatingActionButton(
          heroTag: 'addContactFab',
          shape: const CircleBorder(),
          onPressed: () => openNewContactScreen(context),
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ],
    );
  }
}

Future<void> showDialerSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const DialerSheet(),
  );
}

/// Opens the New Contact form.
///
/// Both "+" entry points come straight here. There is no "Save Manually vs
/// Auto Capture" chooser in between — the form's own two buttons ("Capture
/// Context Automatically" and "Save") make that choice at the end, once the
/// user has actually typed something and knows which they want.
Future<void> openNewContactScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ContactScreen()),
  );
}
