-- Batch 8: connect legacy fault and service history to canonical asset identities.
-- Prerequisite: 202611260002_hospital_asset_foundation.sql
-- Additive compatibility bridge. Legacy device_id columns and app write paths remain unchanged.

begin;

alter table public.faults add column if not exists asset_id uuid;
alter table public.services add column if not exists asset_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'faults_asset_id_fkey'
      and conrelid = 'public.faults'::regclass
  ) then
    alter table public.faults
      add constraint faults_asset_id_fkey
      foreign key (asset_id) references public.assets(id) on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'services_asset_id_fkey'
      and conrelid = 'public.services'::regclass
  ) then
    alter table public.services
      add constraint services_asset_id_fkey
      foreign key (asset_id) references public.assets(id) on delete restrict;
  end if;
end $$;

create index if not exists faults_asset_reported_at_idx
  on public.faults(asset_id, reported_at desc)
  where asset_id is not null;
create index if not exists services_asset_service_date_idx
  on public.services(asset_id, service_date desc)
  where asset_id is not null;

-- Backfill through the stable legacy ID copied into assets. Cast both sides to text
-- to avoid assuming the original device_id database type.
update public.faults f
set asset_id = a.id
from public.devices d
join public.assets a on a.legacy_device_id = d.id::text
where f.asset_id is null
  and f.device_id::text = d.id::text;

update public.services s
set asset_id = a.id
from public.devices d
join public.assets a on a.legacy_device_id = d.id::text
where s.asset_id is null
  and s.device_id::text = d.id::text;

-- Keep the canonical link populated when the existing app continues to write legacy device_id.
create or replace function public.sync_legacy_history_asset_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.device_id is distinct from old.device_id then
      new.asset_id := null;
    end if;
  end if;

  if new.asset_id is null and new.device_id is not null then
    select a.id
      into new.asset_id
    from public.devices d
    join public.assets a on a.legacy_device_id = d.id::text
    where d.id::text = new.device_id::text
    limit 1;
  end if;

  return new;
end;
$$;

drop trigger if exists faults_sync_asset_id on public.faults;
create trigger faults_sync_asset_id
before insert or update of device_id, asset_id on public.faults
for each row execute function public.sync_legacy_history_asset_id();

drop trigger if exists services_sync_asset_id on public.services;
create trigger services_sync_asset_id
before insert or update of device_id, asset_id on public.services
for each row execute function public.sync_legacy_history_asset_id();

commit;

-- Staging verification:
-- select count(*) as faults_missing_asset_link from public.faults where asset_id is null;
-- select count(*) as services_missing_asset_link from public.services where asset_id is null;
-- compare those counts with intentionally unmatched/orphaned legacy device references.
-- insert test fault/service rows through the existing app and confirm asset_id is populated.
-- verify existing fault/service records and QR reporting still work.
