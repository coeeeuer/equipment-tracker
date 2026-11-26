-- READ-ONLY preflight for Central Hospital asset migration review.
-- Run in Supabase SQL Editor against a restored staging copy.
-- This script returns schema metadata and aggregate counts only; it does not return equipment rows,
-- patient information, passwords, API keys or other secrets. It performs no writes.

-- 1) Column definitions for the legacy tables and the existing hospital/generator tables.
select table_name, ordinal_position, column_name, data_type, udt_name,
       is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'devices','faults','services','audits',
    'hospital_locations','generators',
    'generator_fuel_logs','generator_maintenance','generator_faults'
  )
order by table_name, ordinal_position;

-- 2) Primary keys, unique constraints, foreign keys and check constraints.
select n.nspname as schema_name, t.relname as table_name,
       c.conname as constraint_name, c.contype as constraint_type,
       pg_get_constraintdef(c.oid, true) as definition
from pg_constraint c
join pg_class t on t.oid = c.conrelid
join pg_namespace n on n.oid = t.relnamespace
where n.nspname = 'public'
  and t.relname in (
    'devices','faults','services','audits',
    'hospital_locations','generators',
    'generator_fuel_logs','generator_maintenance','generator_faults'
  )
order by t.relname, c.contype, c.conname;

-- 3) Index definitions.
select schemaname, tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in (
    'devices','faults','services','audits',
    'hospital_locations','generators',
    'generator_fuel_logs','generator_maintenance','generator_faults'
  )
order by tablename, indexname;

-- 4) RLS enabled/forced status.
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'devices','faults','services','audits',
    'hospital_locations','generators',
    'generator_fuel_logs','generator_maintenance','generator_faults'
  )
order by c.relname;

-- 5) Existing RLS policies.
select schemaname, tablename, policyname, permissive,
       roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'devices','faults','services','audits',
    'hospital_locations','generators',
    'generator_fuel_logs','generator_maintenance','generator_faults'
  )
order by tablename, policyname;

-- 6) Existing triggers.
select event_object_table as table_name, trigger_name,
       action_timing, event_manipulation, action_statement
from information_schema.triggers
where trigger_schema = 'public'
  and event_object_table in (
    'devices','faults','services','audits',
    'hospital_locations','generators',
    'generator_fuel_logs','generator_maintenance','generator_faults'
  )
order by event_object_table, trigger_name, event_manipulation;

-- 7) Aggregate row counts only.
select 'devices' as table_name, count(*)::bigint as row_count from public.devices
union all select 'faults', count(*)::bigint from public.faults
union all select 'services', count(*)::bigint from public.services
union all select 'audits', count(*)::bigint from public.audits
order by table_name;

-- 8) Department/ward distribution only (no equipment names or serial numbers).
select coalesce(nullif(trim(ward), ''), '[blank ward]') as ward_name,
       count(*)::bigint as device_count
from public.devices
group by coalesce(nullif(trim(ward), ''), '[blank ward]')
order by ward_name;

-- 9) Legacy history references that do not match a current device ID.
select 'faults_without_matching_device' as check_name,
       count(*)::bigint as row_count
from public.faults f
left join public.devices d on d.id::text = f.device_id::text
where d.id is null
union all
select 'services_without_matching_device',
       count(*)::bigint
from public.services s
left join public.devices d on d.id::text = s.device_id::text
where d.id is null
order by check_name;
