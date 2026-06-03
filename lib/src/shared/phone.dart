/// Reduces a phone number to its digits so two numbers can be compared
/// regardless of formatting — spaces, `+`, and country-code punctuation.
///
/// Shared by the new-pickup duplicate-customer check and the order search
/// filter so a digit-only query (what a rider types) matches a formatted stored
/// number (what the form persists). Note this does not reconcile a local
/// leading-zero form with an international country-code form — that needs full
/// phone canonicalisation, tracked separately.
String normalizePhone(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');
