/// Reduces a phone number to its digits so two numbers can be compared
/// regardless of formatting — spaces, `+`, and country-code punctuation.
///
/// Shared by the new-pickup duplicate-customer check and the order search
/// filter so a digit-only query (what a rider types) matches a formatted stored
/// number (what the form persists). Note this does not reconcile a local
/// leading-zero form with an international country-code form — that needs full
/// phone canonicalisation, tracked separately.
String normalizePhone(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

/// Canonicalises a Ugandan mobile number to its 9-digit national significant
/// number (e.g. `700123456`), so the local trunk form (`0700123456`), the
/// international form (`+256 700 123 456` / `256700123456`), and the bare
/// national form all reduce to the same value for matching and validation.
///
/// Uganda-specific: it drops a leading `256` country code, then a single
/// leading `0` trunk prefix. Both are stripped (not either/or) so the redundant
/// `+256 0700…` form — a country code followed by the local trunk zero —
/// reduces correctly too. UG mobile national numbers start with `7`, never
/// `0`/`2`, so this is unambiguous. A complete number yields exactly 9 digits.
String ugandaNationalDigits(String input) {
  var digits = normalizePhone(input);
  if (digits.startsWith('256')) {
    digits = digits.substring(3);
  }
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}
