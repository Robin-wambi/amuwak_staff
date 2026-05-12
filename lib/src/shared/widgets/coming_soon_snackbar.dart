import 'package:flutter/material.dart';

void showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$feature is coming soon.'),
      duration: const Duration(seconds: 2),
    ),
  );
}
