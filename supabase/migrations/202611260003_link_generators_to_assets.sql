-- Batch 3: link existing specialist generator records to the universal asset register.
-- Prerequisite: 202611260002_hospital_asset_foundation.sql
-- Additive and idempotent. No generator history or original generator rows are deleted.

begin;

-- Generator records may legitimately have an unverified/unknown operational status.
alter table public.assets drop constraint if exists assets_operational_status_check;
alter table public.assets add constraint assets_operational_status_check
  check (operational_status in ('unknown','in_service','under_maintenance','out_of_service','in_storage','retired','missing'));

-- Create one canonical asset identity for each existing generator profile.
-- The specialist generators table remains the source for generator-specific specifications/logs.
insert into public.assets (
  hospital_id, asset_code, name, category_id, asset_kind,
  manufacturer, model, serial_number, department_id,
  operational_status, critical, notes, retired_at
)
select
  g.hospital_id,
  'GEN-' || g.asset_code,
  g.name,
  c.id,
  'infrastructure',
  nullif(g.manufacturer,''),
  nullif(g.model,''),
  nullif(g.serial_number,''),
  dep.id,
  case g.operational_status
    when 'operational' then 'in_service'
    when 'under_maintenance' then 'under_maintenance'
    when 'out_of_service' then 'out_of_service'
    when 'retired' then 'retired'
    else 'unknown'
  end,
  true,
  'Canonical asset record linked to the specialist generator register. Generator-specific readings and history remain in the generators module.',
  case when g.operational_status = 'retired' then now() else null end
from public.generators g
left join public.asset_categories c
  on c.hospital_id = g.hospital_id and c.code = 'POWER'
left join public.departments dep
  on dep.hospital_id = g.hospital_id
 and lower(trim(dep.name)) = lower(trim(coalesce(g.location,'')))
where g.hospital_id is not null
on conflict (hospital_id, asset_code) do nothing;

-- Link generator profiles to the canonical asset. Existing non-null links are preserved.
update public.generators g
set asset_id = a.id
from public.assets a
where g.asset_id is null
  and g.hospital_id = a.hospital_id
  and a.asset_code = 'GEN-' || g.asset_code;

create index if not exists generators_asset_id_idx
  on public.generators(asset_id)
  where asset_id is not null;

commit;

-- Staging verification:
-- select count(*) as generator_profiles from public.generators;
-- select count(*) as linked_generator_profiles from public.generators where asset_id is not null;
-- select g.asset_code, g.name, g.asset_id, a.asset_code as canonical_asset_code
-- from public.generators g left join public.assets a on a.id = g.asset_id
-- order by g.asset_code;
