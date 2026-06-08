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
