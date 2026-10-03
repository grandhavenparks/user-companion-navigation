import 'package:flutter/material.dart';

/// Shown every time navigation is about to start.
const String safetyMessage =
    'Be safe and mindful of your surroundings during navigation.';

/// Shows the safety reminder. Returns true when the user taps "Okay" and
/// false when the dialog is closed with the back button.
Future<bool> showSafetyPrompt(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.health_and_safety, size: 48),
      content: const Text(
        safetyMessage,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Okay'),
        ),
      ],
    ),
  );
  return accepted ?? false;
}
