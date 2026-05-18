import 'package:flutter/material.dart';

import '../shared/widgets/app_theme.dart';
import '../shared/widgets/empty_state.dart';

class NewPickupScreen extends StatelessWidget {
  const NewPickupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('New pickup'),
      ),
      body: const EmptyState(
        icon: Icons.add_location_alt_outlined,
        headline: 'New pickup will land here soon.',
        subtitle: 'For now, pickups come from the dashboard list.',
      ),
    );
  }
}
