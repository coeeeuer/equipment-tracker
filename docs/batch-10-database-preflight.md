# Batch 10 — Database preflight evidence

Run `supabase/verification/central_hospital_preflight.sql` in the restored staging copy before applying migrations 001–007.

The script is read-only. It returns:
- Legacy table columns and types.
- Primary keys, unique constraints, foreign keys and check constraints.
- Existing indexes.
- RLS enabled/forced status and policies.
- Existing triggers.
- Aggregate row counts.
- Ward distribution counts.
- Counts of fault/service rows whose `device_id` no longer matches a current device.

It does not return equipment names, serial numbers, patient records, passwords, API keys or secrets, and it does not modify the database.

## What to share back

Share the result sets from sections 1–6 and 7–9, or export the result as CSV/JSON. If the output is too large, share the columns, constraints, RLS policies and trigger results first.

The purpose is to verify the assumptions in migration 002 and migration 007 before running either. If a legacy column, type, constraint or policy differs from what the app and migrations expect, the migration should be adjusted before execution.

Do not run the migration sequence on production just to obtain these results. Use a restored staging copy or a read-only connection to inspect the existing schema.
