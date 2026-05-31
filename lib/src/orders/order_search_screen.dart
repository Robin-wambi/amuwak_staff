import 'package:flutter/material.dart';

import '../shared/widgets/empty_state.dart';

class OrderSearchScreen extends StatelessWidget {
  const OrderSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        title: const Text('Order search'),
      ),
      body: const EmptyState(
        icon: Icons.search_off_rounded,
        headline: 'Order search coming soon.',
        subtitle: 'For now, browse orders on the dashboard.',
      ),
    );
  }
}
