-- 0002_staff_and_customers_test.sql
-- Verify schema of staff and customers and the staff.role CHECK constraint.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

SELECT has_table('public', 'staff', 'staff table exists');
SELECT has_column('public', 'staff', 'username', 'staff.username exists');
SELECT col_is_unique('public', 'staff', ARRAY['username'], 'staff.username is unique');
SELECT col_has_check('public', 'staff', 'role', 'staff.role has CHECK constraint');

SELECT has_table('public', 'customers', 'customers table exists');
SELECT has_column('public', 'customers', 'phone', 'customers.phone exists');
SELECT has_column('public', 'customers', 'deleted_at', 'customers.deleted_at exists');

-- Reject role values outside the allowed set
PREPARE bad_role AS
  INSERT INTO public.staff (id, username, display_name, role)
  VALUES (gen_random_uuid(), 'bad_role_user', 'X', 'super_admin');
SELECT throws_ok('bad_role', '23514',
  NULL, 'inserting an invalid role raises check_violation');

SELECT * FROM finish();
ROLLBACK;
