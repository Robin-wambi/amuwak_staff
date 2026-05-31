import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/login_screen.dart';
import '../auth/session.dart';
import '../auth/sign_out.dart';
import '../notifications/notifications_screen.dart';
import '../orders/geo_services.dart';
import '../orders/new_pickup_result.dart';
import '../orders/new_pickup_screen.dart';
import '../orders/order.dart';
import '../orders/order_details_screen.dart';
import '../orders/order_list_extensions.dart';
import '../orders/order_search_screen.dart';
import '../orders/order_status.dart';
import '../orders/proof/barcode_reader.dart';
import '../orders/proof/pickup_capture_screen.dart';
import '../orders/proof/proof_photo_storage.dart';
import '../reports/daily_report_screen.dart';
import '../shared/theme/app_card.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_radii.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/theme/status_colors.dart';
import '../shared/uuid.dart';
import '../shared/widgets/sync_status_banner.dart';
import '../sync/repository_providers.dart';
import '../sync/sync_errors_provider.dart';
import '../sync/sync_errors_screen.dart';
import '../sync/sync_orchestrator_provider.dart';
import '../sync/sync_status.dart';

typedef RetrieveLostPhotoFn = Future<bool> Function();

/// Optional injectable for tests: lets a test pump the dashboard, tap the
/// sign-out menu item, and observe the call WITHOUT having to override every
/// transitive Riverpod provider that `signOutAndReset` would resolve through.
typedef SignOutFn = Future<void> Function(WidgetRef ref);

class StaffDashboardScreen extends ConsumerStatefulWidget {
  const StaffDashboardScreen({
    super.key,
    this.retrieveLostPhoto,
    this.signOut,
  });

  // On Android the OS may kill MainActivity while the camera is open, dropping
  // the photo bytes silently. We check on startup so the rider knows to retry
  // instead of believing the capture succeeded. iOS is a no-op (empty response).
  final RetrieveLostPhotoFn? retrieveLostPhoto;

  /// Test seam — defaults to the real `signOutAndReset(...)` flow wired
  /// through the auth + orchestrator + database providers.
  final SignOutFn? signOut;

  @override
  ConsumerState<StaffDashboardScreen> createState() =>
      _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends ConsumerState<StaffDashboardScreen> {
  int _selectedTabIndex = 0;

  // Backend deferred per SPEC-000: photos live in memory only. Swap for
  // `createDefaultProofPhotoStorage()` once the upload endpoint is available.
  final ProofPhotoStorage _photoStorage = InMemoryProofPhotoStorage();
  final ImagePicker _imagePicker = ImagePicker();
  final CameraViewBuilder _cameraViewBuilder = mobileScannerCameraViewBuilder();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final retriever = widget.retrieveLostPhoto ?? _defaultRetrieveLostPhoto;
      final lost = await retriever();
      if (!mounted || !lost) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your last photo capture was interrupted. Please retry.',
          ),
        ),
      );
    });
  }

  Future<bool> _defaultRetrieveLostPhoto() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty) return false;
      return response.file != null ||
          (response.files?.isNotEmpty ?? false) ||
          response.exception != null;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>?> _pickPhoto() async {
    final XFile? file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// Confirms intent, then either runs the injected `signOut` callback (test
  /// seam) or wires `signOutAndReset` through the real orchestrator / db /
  /// auth providers. On success, replaces the navigation stack with
  /// LoginScreen so the user can re-authenticate. On failure, surfaces a
  /// SnackBar — leaving them on a half-cleared dashboard would be worse.
  Future<void> _onSignOutPressed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Sign out and clear local data on this device? Any '
          'pending uploads will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final signOut = widget.signOut ?? _defaultSignOut;
      await signOut(ref);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not sign out. Please try again.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  /// Production wiring: resolves the orchestrator, database, and auth service
  /// from Riverpod and hands them to [signOutAndReset]. Kept as a static-ish
  /// method (instance method that only touches `ref`) so the test override
  /// path can replace this entirely.
  Future<void> _defaultSignOut(WidgetRef ref) {
    return signOutAndReset(
      orchestrator: ref.read(syncOrchestratorProvider),
      db: ref.read(appDatabaseProvider),
      auth: ref.read(authServiceProvider),
    );
  }

  Future<void> _handleNewPickup() async {
    final staffId = ref.read(currentUserIdProvider);
    if (staffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired — please sign in again.'),
        ),
      );
      return;
    }
    final result = await Navigator.of(context).push<NewPickupResult>(
      MaterialPageRoute(
        builder: (_) => NewPickupScreen(
          customersRepo: ref.read(customersRepositoryProvider),
          ordersRepo: ref.read(ordersRepositoryProvider),
          actorStaffId: staffId,
          clock: DateTime.now,
          orderIdGenerator: defaultUuidV4,
          customerIdGenerator: defaultUuidV4,
          geolocate: createDefaultGeolocate(),
          reverseGeocode: createDefaultReverseGeocode(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (!result.startPickupNow) return;
    // The order was just written to Drift; the stream emits asynchronously
    // after the transaction settles. Poll the snapshot a few times before
    // giving up — without this the first pickup after app start lands on
    // the dashboard instead of PickupCaptureScreen because the stream
    // hadn't pre-emitted the order yet.
    LaundryOrder? newOrder;
    for (var attempt = 0; attempt < 10; attempt++) {
      final orders = ref.read(ordersStreamProvider).valueOrNull ?? const [];
      for (final o in orders) {
        if (o.orderId == result.orderId) {
          newOrder = o;
          break;
        }
      }
      if (newOrder != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    if (newOrder == null || !mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PickupCaptureScreen(
          order: newOrder!,
          photoStorage: _photoStorage,
          pickPhoto: _pickPhoto,
          ordersRepo: ref.read(ordersRepositoryProvider),
          proofEventsRepo: ref.read(proofEventsRepositoryProvider),
          actorStaffId: staffId,
        ),
      ),
    );
  }

  Future<void> _openOrderDetails(LaundryOrder order) async {
    // Critical: actorStaffId must NEVER be empty downstream. Postgres has
    // intake_recorded_by/created_by as NOT NULL REFERENCES staff(id), so an
    // empty string would FK-fail the outbox dispatch and silently dead-letter
    // the row. Refuse to open details if the session hasn't hydrated yet
    // (cold-start race) or has expired.
    final staffId = ref.read(currentUserIdProvider);
    if (staffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired — please sign in again.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(
          order: order,
          photoStorage: _photoStorage,
          pickPhoto: _pickPhoto,
          cameraViewBuilder: _cameraViewBuilder,
          ordersRepo: ref.read(ordersRepositoryProvider),
          proofEventsRepo: ref.read(proofEventsRepositoryProvider),
          actorStaffId: staffId,
        ),
      ),
    );
    // No-op on return — the stream picks up the write (after Task 10/11/12
    // wire writes through the repositories).
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTabIndex = index;
    });
  }

  void _openSyncErrors() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SyncErrorsScreen()),
    );
  }

  String get _title {
    switch (_selectedTabIndex) {
      case 1:
        return 'Orders';
      case 2:
        return 'Daily report';
      case 3:
        return 'Account';
      default:
        return 'Amuwak Staff';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersStreamProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          Consumer(
            builder: (context, ref, _) {
              final count = ref.watch(syncErrorCountProvider);
              return IconButton(
                tooltip: 'Sync errors',
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const SyncErrorsScreen()),
                ),
                icon: Badge(
                  label: count > 0 ? Text('$count') : null,
                  isLabelVisible: count > 0,
                  child: const Icon(Icons.error_outline_rounded),
                ),
              );
            },
          ),
        ],
      ),
      body: _DashboardTabShell(
        onShowErrors: _openSyncErrors,
        child: switch (_selectedTabIndex) {
          1 => ordersAsync.when(
              data: (orders) => _OrdersBody(
                orders: orders,
                onOrderTap: _openOrderDetails,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _ErrorRetry(
                onRetry: () => ref.invalidate(ordersStreamProvider),
              ),
            ),
          2 => ordersAsync.when(
              data: (orders) => DailyReportView(orders: orders),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _ErrorRetry(
                onRetry: () => ref.invalidate(ordersStreamProvider),
              ),
            ),
          3 => _AccountTab(onSignOut: _onSignOutPressed),
          _ => ordersAsync.when(
              data: (orders) => _DashboardBody(
                orders: orders,
                onOrderTap: _openOrderDetails,
                onNewPickup: _handleNewPickup,
                onShowReport: () => _selectTab(2),
              ),
              loading: () => _DashboardLoadingBody(
                onNewPickup: _handleNewPickup,
                onShowReport: () => _selectTab(2),
              ),
              error: (_, __) => _ErrorRetry(
                onRetry: () => ref.invalidate(ordersStreamProvider),
              ),
            ),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private body widgets
// ---------------------------------------------------------------------------

class _DashboardTabShell extends StatelessWidget {
  const _DashboardTabShell({required this.child, this.onShowErrors});

  final Widget child;
  final VoidCallback? onShowErrors;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          SyncStatusBanner(onShowErrors: onShowErrors),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.orders,
    required this.onOrderTap,
    required this.onNewPickup,
    required this.onShowReport,
  });

  final List<LaundryOrder> orders;
  final void Function(LaundryOrder) onOrderTap;
  final VoidCallback onNewPickup;
  final VoidCallback onShowReport;

  @override
  Widget build(BuildContext context) {
    final totalOrders = orders.length;
    final pendingPickup = orders.countByStatus(OrderStatus.pendingPickup);
    final inProgress = orders.countByStatus(OrderStatus.inProgress);
    final readyForDelivery = orders.countByStatus(OrderStatus.readyForDelivery);
    final completed = orders.countByStatus(OrderStatus.completed);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        const _DashboardHeader(),
        const SizedBox(height: AppSpacing.xl),
        _SummaryGrid(
          totalOrders: totalOrders,
          pendingPickup: pendingPickup,
          inProgress: inProgress,
          readyForDelivery: readyForDelivery,
          completed: completed,
        ),
        const SizedBox(height: AppSpacing.xxl),
        _QuickActions(
          onNewPickup: onNewPickup,
          onShowReport: onShowReport,
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          'Assigned orders',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final order in orders) ...[
          _OrderCard(order: order, onTap: () => onOrderTap(order)),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _DashboardLoadingBody extends StatelessWidget {
  const _DashboardLoadingBody({
    required this.onNewPickup,
    required this.onShowReport,
  });

  final VoidCallback onNewPickup;
  final VoidCallback onShowReport;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        const _DashboardHeader(),
        const SizedBox(height: AppSpacing.xl),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: LinearProgressIndicator(),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _QuickActions(
          onNewPickup: onNewPickup,
          onShowReport: onShowReport,
        ),
      ],
    );
  }
}

class _OrdersBody extends StatelessWidget {
  const _OrdersBody({
    required this.orders,
    required this.onOrderTap,
  });

  final List<LaundryOrder> orders;
  final void Function(LaundryOrder) onOrderTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        Text(
          'Assigned orders',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final order in orders) ...[
          _OrderCard(order: order, onTap: () => onOrderTap(order)),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _AccountTab extends StatelessWidget {
  const _AccountTab({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg + 2), // original was 18
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                child: Icon(
                  Icons.person_rounded,
                  color: colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Staff account',
                      style: textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Operations workspace',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg - 2), // original was 14
        _AccountDetailRow(
          icon: Icons.badge_outlined,
          label: 'Role',
          value: 'Laundry operations staff',
        ),
        const SizedBox(height: AppSpacing.sm + 2), // original was 10
        _AccountDetailRow(
          icon: Icons.schedule_outlined,
          label: 'Shift',
          value: 'Today',
        ),
        const SizedBox(height: AppSpacing.lg + 2), // original was 18
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _AccountDetailRow extends StatelessWidget {
  const _AccountDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load orders. Please try again.'),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unchanged private widgets (header, grid, cards, chips, actions)
// ---------------------------------------------------------------------------

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg + 2), // original was 18
      decoration: BoxDecoration(
        color: AppColors.surfaceBrand,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: [
          BoxShadow(
            color: AppColors.surfaceBrand.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.white,
            child: Icon(
              Icons.local_laundry_service_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Staff Workspace',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "Today's laundry operations",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.totalOrders,
    required this.pendingPickup,
    required this.inProgress,
    required this.readyForDelivery,
    required this.completed,
  });

  final int totalOrders;
  final int pendingPickup;
  final int inProgress;
  final int readyForDelivery;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Assigned',
                value: '$totalOrders',
                icon: Icons.assignment_outlined,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _SummaryCard(
                title: OrderStatus.pendingPickup.label,
                value: '$pendingPickup',
                icon: Icons.local_shipping_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: OrderStatus.inProgress.label,
                value: '$inProgress',
                icon: Icons.timelapse_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _SummaryCard(
                title: OrderStatus.readyForDelivery.label,
                value: '$readyForDelivery',
                icon: Icons.checkroom_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SummaryCard(
          title: 'Completed today',
          value: '$completed',
          icon: Icons.check_circle_outline_rounded,
          wide: true,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    this.wide = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: SizedBox(
        width: wide ? double.infinity : null,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: AppSpacing.md + 1), // original was 13
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: textTheme.headlineMedium,
                  ),
                  Text(
                    title,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onNewPickup,
    required this.onShowReport,
  });

  final VoidCallback onNewPickup;
  final VoidCallback onShowReport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick actions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'New pickup',
                icon: Icons.add_location_alt_outlined,
                onTap: onNewPickup,
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2), // original was 10
            Expanded(
              child: _ActionButton(
                label: 'Check order',
                icon: Icons.search_rounded,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const OrderSearchScreen()),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2), // original was 10
            Expanded(
              child: _ActionButton(
                label: 'Report',
                icon: Icons.bar_chart_rounded,
                onTap: onShowReport,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.sm,
      ),
      child: Column(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final LaundryOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusPair = (Theme.of(context).extension<StatusColors>() ??
            StatusColors.light)
        .of(order.status);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.field - 2),
                ),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md + 1), // original was 13
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.customerName,
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs / 2), // original was 2
                    Text(
                      '${order.orderCode} - ${order.serviceType.label}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryText,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg - 2), // original was 14
          Row(
            children: [
              _InfoChip(
                icon: Icons.access_time_rounded,
                label: order.timeLabel,
              ),
              const SizedBox(width: AppSpacing.sm),
              _InfoChip(
                icon: Icons.inventory_2_outlined,
                label: '${order.itemCount} items',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: statusPair.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
            child: Text(
              order.status.label,
              style: TextStyle(
                color: statusPair.onColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2, // original was 10
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
