import 'package:flutter/material.dart';

import '../../shared/format_ugx.dart';
import '../../shared/theme/app_card.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import 'line_item.dart';

/// Editable list of free-form line items, with an "Add item" button. Stateless:
/// the parent owns the list and re-renders on change.
class LineItemsEditor extends StatelessWidget {
  const LineItemsEditor({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final List<LineItem> items;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: Text(items[i].name)),
                Text(formatUgx(items[i].amountUgx)),
                IconButton(
                  key: Key('remove_line_item_$i'),
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          ),
        TextButton.icon(
          key: const Key('add_line_item'),
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
      ],
    );
  }
}

/// Prominent total display with an optional "Provisional" badge (shown until a
/// final weight is recorded).
class TotalCard extends StatelessWidget {
  const TotalCard({
    super.key,
    required this.totalUgx,
    required this.isProvisional,
  });

  final int totalUgx;
  final bool isProvisional;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total', style: textTheme.bodySmall),
              Text(formatUgx(totalUgx), style: textTheme.headlineMedium),
            ],
          ),
          if (isProvisional)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.secondaryText.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('Provisional'),
            ),
        ],
      ),
    );
  }
}

/// Shows a bottom sheet collecting a line-item name + amount. Returns the
/// validated [LineItem], or null if dismissed without saving. Invalid input
/// keeps the sheet open with an inline error rather than silently closing, so
/// the rider can tell a rejected entry from a deliberate cancel.
Future<LineItem?> showAddLineItemSheet(BuildContext context) {
  return showModalBottomSheet<LineItem>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const _AddLineItemSheet(),
  );
}

/// Sheet body for [showAddLineItemSheet]. A stateful widget so its controllers
/// are disposed via [State.dispose] once the sheet has fully closed — disposing
/// them when the future completes would free them mid exit-animation while the
/// fields are still mounted.
class _AddLineItemSheet extends StatefulWidget {
  const _AddLineItemSheet();

  @override
  State<_AddLineItemSheet> createState() => _AddLineItemSheetState();
}

class _AddLineItemSheetState extends State<_AddLineItemSheet> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  String? _nameError;
  String? _amountError;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final amount = int.tryParse(_amountController.text.trim());
    final nextNameError = name.isEmpty ? 'Enter an item name' : null;
    final nextAmountError =
        (amount == null || amount < 0) ? 'Enter a valid amount' : null;
    if (nextNameError != null || nextAmountError != null) {
      setState(() {
        _nameError = nextNameError;
        _amountError = nextAmountError;
      });
      return;
    }
    Navigator.pop(context, LineItem(name: name, amountUgx: amount!));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('line_item_name'),
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Item (e.g. Blanket)',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('line_item_amount'),
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Amount (UGX)',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            key: const Key('line_item_save'),
            onPressed: _submit,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
