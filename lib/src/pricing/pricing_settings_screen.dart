import 'package:flutter/material.dart';

import '../shared/format_ugx.dart';
import '../shared/theme/app_spacing.dart';
import 'pricing_settings.dart';

typedef LoadSettingsFn = Future<PricingSettings> Function();
typedef SaveRateFn = Future<void> Function(double ratePerKgUgx);

class PricingSettingsScreen extends StatefulWidget {
  const PricingSettingsScreen({
    super.key,
    required this.load,
    required this.save,
  });

  final LoadSettingsFn load;
  final SaveRateFn save;

  @override
  State<PricingSettingsScreen> createState() => _PricingSettingsScreenState();
}

class _PricingSettingsScreenState extends State<PricingSettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.load();
      if (!mounted) return;
      setState(() {
        _controller.text = s.defaultRatePerKgUgx.round().toString();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pricing settings missing — contact admin.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final rate = double.tryParse(_controller.text.trim());
    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a rate greater than 0.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.save(rate);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text('Default rate set to ${formatUgx(rate.round())}/kg.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save — please retry.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pricing settings')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: [
                      Text('Default rate per kg (UGX)',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const Key('settings_rate'),
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        key: const Key('settings_save'),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
