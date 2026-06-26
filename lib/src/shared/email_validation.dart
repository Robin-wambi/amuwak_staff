/// Email shape check shared by the auth + invite forms. Mirrors the server-side
/// regex in `supabase/functions/invite-staff/index.ts` so the client rejects the
/// same malformed addresses (e.g. `a@`, `@b`) before a round-trip, giving a
/// clean field error instead of a server error.
final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isValidEmail(String email) => _emailRegExp.hasMatch(email.trim());
