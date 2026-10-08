-- Path A helper: least-privilege Postgres role for GoTrue.
-- Run as a superuser against your existing database, then point
-- GOTRUE_DB_DATABASE_URL at this role. GoTrue runs its own migrations
-- into the `auth` schema on first start.
--
-- Replace CHANGE_ME with a strong password before running.

DO $$BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin LOGIN PASSWORD 'CHANGE_ME';
  END IF;
END$$;

CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
ALTER ROLE supabase_auth_admin SET search_path = auth, public;
-- GoTrue also needs to create extensions in some setups; grant if needed:
-- GRANT CREATE ON DATABASE postgres TO supabase_auth_admin;
