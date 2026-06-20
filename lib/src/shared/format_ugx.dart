/// Formats an integer UGX amount for display: `USh 8,000`. No decimal places
/// (UGX has no practical subdivision). Negative values keep the sign after the
/// prefix: `USh -5,000`. Single source of truth for money rendering — every
/// screen uses this so separators and the prefix never drift.
String formatUgx(int amountUgx) {
  final negative = amountUgx < 0;
  final digits = amountUgx.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return 'USh ${negative ? '-' : ''}$buffer';
}

/// Formats a percentage without a trailing ".0" (e.g. `30`, not `30.0`) while
/// keeping a real fraction (e.g. `12.5`). Shared by the pricing settings and
/// new-pickup screens so the express-percentage display never drifts.
///
/// Uses an epsilon comparison rather than exact float equality so a value that
/// is whole but carries tiny arithmetic noise (e.g. `30.000000000001`) still
/// renders as `30` instead of leaking the float error.
String formatPct(double pct) =>
    (pct - pct.roundToDouble()).abs() < 1e-9
        ? pct.round().toString()
        : pct.toString();
