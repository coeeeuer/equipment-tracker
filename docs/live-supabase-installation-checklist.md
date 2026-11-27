# Live Supabase installation checklist

This checklist distinguishes repository delivery from actual database installation. A GitHub merge alone never means a migration is installed.

## Correct production project

- Project ref: `kqayyuanjcbgopffbemt`
- Project name in Supabase: Equipment Tracker project
- Region: `eu-west-1`
- Do not confuse with the unrelated `hems-demo` project.

## Latest verified live status

Last checked: 2026-11-27.

- Project health: `ACTIVE_HEALTHY`
- Supabase migration history contains only `20261126195147_archive_pre_reset_equipment_tracker_test_data`.
- Public schema contains only legacy `devices`, `faults`, `services` and `audits` tables.
- No canonical hospital foundation tables are installed.
- No `asset_work_orders` table is installed.
- No canonical transfer RPC is installed.
- Legacy table counts at the check: devices 0, faults 0, services 0, audits 0.
- Existing Auth account and `fault-photos` storage bucket/files were retained during the test-data cleanup.

## Migration status

| Repository migration | Meaning | Live status |
|---|---|---|
| 001 Central Hospital modules | Hospital, roles and module foundation | Not installed |
| 002 Hospital asset foundation | Assets, departments, locations, categories, generators, audit and documents | Not installed |
| 003 Generator links | Generator-to-asset links | Not installed |
| 004 Asset audit triggers | Canonical asset audit trail | Not installed |
| 005 Department membership RLS | Department access boundaries | Not installed |
| 006 Asset code generation | Concurrency-safe asset codes | Not installed |
| 007 Legacy history links | Link legacy faults/services to assets | Not installed |
| 008 Legacy RPC hardening | Restrict internal RPC execution | Not installed |
| 009 Atomic asset transfer | Transfer RPC | Not installed |
| 010 Asset work-order history | Fault/repair/PM/calibration records | Not installed |
| 011 Capacity/search indexes | Trigram and composite indexes | Not installed |

## How installation will be confirmed

A migration is marked installed only after all of these are true:

1. Supabase migration history shows the migration version/name.
2. The expected table, function, index or policy is present in the live database.
3. A targeted, non-destructive verification query succeeds.
4. The application workflow using it is tested with the intended role.

For a table migration, verify the table via Supabase Table Editor or SQL:
```sql
select to_regclass('public.asset_work_orders') as work_order_table;
```

For the transfer RPC:
```sql
select to_regprocedure(
  'public.transfer_asset(uuid,uuid,uuid,timestamp with time zone,text)'
) as transfer_function;
```

For the migration ledger, use Supabase CLI `supabase migration list` (linked to the correct project) or the Supabase migration history tool/API. The ChatGPT Supabase migration list is also checked as part of this project workflow.

## Production rollout gate

Do not apply the hospital migrations to production merely because they are merged. Before production:
- Review and verify the real legacy schema, triggers, policies and storage setup.
- Obtain a genuine restorable backup; the `migration_archive` schema is not a complete Supabase backup.
- Resolve the HOD's decisions about staff roles and departmental permissions.
- Test the full sequence on an isolated staging copy. Do not create a paid Supabase branch without the user's explicit approval.
- Verify public QR lookup and fault reporting remain functional.
- Verify legacy records and files remain intact.
- Get explicit hospital approval for production installation.

Update this file after each real installation and verification. Never change a status to installed based only on a GitHub merge.
