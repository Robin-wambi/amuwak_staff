// invite-staff
// -----------------------------------------------------------------------------
// Manager-only endpoint that invites a new staff member. Runs server-side with
// the service-role key so the privileged Supabase admin invite API is never
// exposed to the client.
//
// Flow:
//   1. Identify the caller from their JWT (Authorization header).
//   2. Confirm the caller is an ACTIVE MANAGER (the security boundary — the
//      Flutter UI only hides the button; this is what actually enforces it).
//   3. Validate the payload and reject a duplicate username.
//   4. inviteUserByEmail() — creates an auth user in the "invited" state and
//      emails them a link to set a password (which also confirms their email).
//   5. Insert the matching staff row (id == auth user id) with the chosen role.
//      If the insert fails, delete the just-invited auth user so we don't leave
//      an orphan with no staff row.
//
// Env (provided by Supabase automatically): SUPABASE_URL, SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY. Optional: INVITE_REDIRECT_URL (where the invite
// link lands — defaults to the project Site URL when unset).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ALLOWED_ROLES = ['driver', 'in_shop', 'manager'] as const;
type Role = (typeof ALLOWED_ROLES)[number];

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const redirectTo = Deno.env.get('INVITE_REDIRECT_URL') ?? undefined;

  // 1. Identify the caller from their bearer token.
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) return json({ error: 'Missing authorization' }, 401);

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user: caller },
    error: callerErr,
  } = await callerClient.auth.getUser();
  if (callerErr || !caller) {
    return json({ error: 'Not signed in' }, 401);
  }

  // Service-role client for the privileged reads/writes below.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 2. The caller must be an active manager.
  const { data: callerStaff } = await admin
    .from('staff')
    .select('role, active')
    .eq('id', caller.id)
    .maybeSingle();
  if (!callerStaff || callerStaff.active !== true ||
      callerStaff.role !== 'manager') {
    return json({ error: 'Only managers can invite staff' }, 403);
  }

  // 3. Validate the payload.
  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }

  const email = String(payload.email ?? '').trim().toLowerCase();
  const displayName = String(payload.display_name ?? '').trim();
  const username = String(payload.username ?? '').trim().toLowerCase();
  const role = String(payload.role ?? '') as Role;

  if (!EMAIL_RE.test(email)) return json({ error: 'Enter a valid email' }, 400);
  if (!displayName) return json({ error: 'Display name is required' }, 400);
  if (!username) return json({ error: 'Username is required' }, 400);
  if (!ALLOWED_ROLES.includes(role)) {
    return json({ error: 'Invalid role' }, 400);
  }

  // 3b. Reject a duplicate username before inviting, so we don't create an auth
  // user we'd then have to roll back.
  const { data: existing } = await admin
    .from('staff')
    .select('id')
    .eq('username', username)
    .is('deleted_at', null)
    .maybeSingle();
  if (existing) return json({ error: 'Username already taken' }, 409);

  // 4. Invite the user (sends the email; confirms email on acceptance).
  const { data: invited, error: inviteErr } =
    await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
  if (inviteErr || !invited?.user) {
    // Most commonly: the email already has an account.
    return json(
      { error: inviteErr?.message ?? 'Could not send the invite' },
      409,
    );
  }

  // 5. Create the staff row keyed to the new auth user.
  const { error: insertErr } = await admin.from('staff').insert({
    id: invited.user.id,
    username,
    display_name: displayName,
    role,
    active: true,
  });
  if (insertErr) {
    // Roll back the orphaned auth user so the manager can retry cleanly.
    await admin.auth.admin.deleteUser(invited.user.id);
    const duplicate = insertErr.code === '23505';
    return json(
      {
        error: duplicate
          ? 'Username already taken'
          : 'Could not create the staff record',
      },
      duplicate ? 409 : 500,
    );
  }

  return json({ ok: true, user_id: invited.user.id }, 200);
});
