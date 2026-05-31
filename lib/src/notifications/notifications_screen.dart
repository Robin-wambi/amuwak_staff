import 'package:flutter/material.dart';

import '../shared/widgets/empty_state.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        title: const Text('Notifications'),
      ),
      body: const EmptyState(
        icon: Icons.notifications_off_outlined,
        headline: 'No notifications yet.',
        subtitle: "We'll let you know when something needs your attention.",
      ),
    );
  }
}
