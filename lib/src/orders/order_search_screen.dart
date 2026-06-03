import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/theme/app_spacing.dart';
import '../shared/widgets/empty_state.dart';
import '../sync/repository_providers.dart';
import 'order.dart';
import 'order_list_extensions.dart';
import 'order_status.dart';
import 'proof/barcode_reader.dart';
import 'widgets/barcode_search_scan_screen.dart';
import 'widgets/order_card.dart';

/// Lets a rider find one known order fast: live text filtering over the
/// orders stream (by code, customer name, phone, or address), with a
/// browsable "active orders" zero-state when the field is empty.
///
/// [onOrderTap] is the dashboard's order-details opener (it carries the
/// session check + repository wiring), so this screen never re-implements
/// navigation into [OrderDetailsScreen]. [cameraViewBuilder] backs the
/// barcode scan-to-search action.
class OrderSearchScreen extends ConsumerStatefulWidget {
  const OrderSearchScreen({
    super.key,
    required this.onOrderTap,
    required this.cameraViewBuilder,
  });

  final void Function(LaundryOrder order) onOrderTap;
  final CameraViewBuilder cameraViewBuilder;

  @override
  ConsumerState<OrderSearchScreen> createState() => _OrderSearchScreenState();
}

class _OrderSearchScreenState extends ConsumerState<OrderSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
    _focusNode.requestFocus();
  }

  Future<void> _openScanner() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BarcodeSearchScanScreen(
          cameraViewBuilder: widget.cameraViewBuilder,
        ),
      ),
    );
    if (code == null || !mounted) return;
    _controller.text = code;
    setState(() => _query = code);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersStreamProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Search by code, name, phone…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Clear',
                    onPressed: _clear,
                  ),
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Scan order tag',
            onPressed: _openScanner,
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const EmptyState(
          icon: Icons.error_outline_rounded,
          headline: "Couldn't load orders",
          subtitle: 'Please try again.',
        ),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(List<LaundryOrder> orders) {
    final query = _query.trim();

    if (query.isEmpty) {
      final active = orders
          .where((o) => o.status != OrderStatus.completed)
          .toList(growable: false);
      if (active.isEmpty) {
        return const EmptyState(
          icon: Icons.inbox_outlined,
          headline: 'No active orders',
          subtitle: 'Search to find any order by code, name, phone, or address.',
        );
      }
      return _ResultsList(
        header: 'Active orders',
        orders: active,
        onOrderTap: widget.onOrderTap,
      );
    }

    final matches = orders.searchBy(query);
    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        headline: 'No orders found',
        subtitle: 'Nothing matches "$query".',
      );
    }
    return _ResultsList(orders: matches, onOrderTap: widget.onOrderTap);
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.orders,
    required this.onOrderTap,
    this.header,
  });

  final List<LaundryOrder> orders;
  final void Function(LaundryOrder order) onOrderTap;
  final String? header;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: orders.length + (header == null ? 0 : 1),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        if (header != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(header!, style: Theme.of(context).textTheme.titleMedium),
          );
        }
        final order = orders[header == null ? index : index - 1];
        return OrderCard(order: order, onTap: () => onOrderTap(order));
      },
    );
  }
}
