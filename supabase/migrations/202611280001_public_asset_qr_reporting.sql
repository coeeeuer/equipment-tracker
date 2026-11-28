-- Public QR reporting for canonical hospital assets.
-- Depends on migrations 001-010, including public.assets, departments and asset_work_orders.
-- Public functions disclose only fields needed by a scanned asset label and accept
-- a bounded fault report. They do not grant anon table access.

alter table public.asset_work_orders
  add column if not exists reporter_name text;

comment on column public.asset_work_orders.reporter_name
  is 'Optional name supplied by a person submitting a public QR fault report.';

-- Backward-compatible public lookup for legacy EQ-xxxx labels.
-- The new department_id value lets the client detect stale department IDs,
-- rather than relying only on a matching department name.
create or replace function public.get_device_public_v2(p_id text)
returns table (
  id text,
  name text,
  ward text,
  category text,
  critical boolean,
  fault_stage text,
  fault_since date,
  department_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    d.id,
    d.name,
    d.ward,
    d.category,
    d.critical,
    f.stage,
    f.reported_at,
    dep.id as department_id
  from public.devices d
  left join public.hospitals h
    on h.slug = 'central-hospital'
  left join public.departments dep
    on dep.hospital_id = h.id
   and lower(trim(dep.name)) = lower(trim(d.ward))
  left join lateral (
    select x.stage, x.reported_at
    from public.faults x
    where x.device_id = d.id
      and x.resolved_at is null
    order by x.reported_at
    limit 1
  ) f on true
  where d.id = upper(trim(p_id))
    and not d.retired
  limit 1;
$$;

-- Lookup for canonical asset QR labels. The UUID in the QR is the stable asset
-- identity; the returned current department is compared with the encoded one.
create or replace function public.get_asset_public(p_asset_id uuid)
returns table (
  asset_id uuid,
  asset_code text,
  asset_name text,
  department_id uuid,
  department_name text,
  asset_kind text,
  model text,
  serial_number text,
  critical boolean,
  operational_status text,
  open_fault_status text,
  open_fault_date timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    a.asset_code,
    a.name,
    a.department_id,
    coalesce(dep.name, 'Department not assigned'),
    a.asset_kind,
    a.model,
    a.serial_number,
    a.critical,
    a.operational_status,
    wo.status,
    wo.reported_at
  from public.assets a
  left join public.departments dep
    on dep.id = a.department_id
   and dep.hospital_id = a.hospital_id
  left join lateral (
    select w.status, w.reported_at
    from public.asset_work_orders w
    where w.asset_id = a.id
      and w.hospital_id = a.hospital_id
      and w.work_order_type = 'fault'
      and w.status in ('open', 'in_progress', 'awaiting_parts')
    order by w.reported_at desc
    limit 1
  ) wo on true
  where a.id = p_asset_id
    and a.retired_at is null
    and a.operational_status <> 'retired'
  limit 1;
$$;

-- Public fault submission for a QR-scanned canonical asset. A row lock prevents
-- two simultaneous submissions from creating duplicate active fault records.
-- Anonymous reports are entered without an Auth user; the optional reporter name
-- is kept separately from the actual fault description.
create or replace function public.report_asset_fault(
  p_asset_id uuid,
  p_desc text,
  p_priority text default 'Normal',
  p_reporter text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hospital_id uuid;
  v_operational_status text;
begin
  if p_asset_id is null
     or p_desc is null
     or char_length(trim(p_desc)) = 0
     or char_length(p_desc) > 1000 then
    return 'invalid';
  end if;

  select a.hospital_id, a.operational_status
    into v_hospital_id, v_operational_status
  from public.assets a
  where a.id = p_asset_id
    and a.retired_at is null
  for update;

  if not found or v_hospital_id is null or v_operational_status = 'retired' then
    return 'not_found';
  end if;

  if exists (
    select 1
    from public.asset_work_orders w
    where w.asset_id = p_asset_id
      and w.hospital_id = v_hospital_id
      and w.work_order_type = 'fault'
      and w.status in ('open', 'in_progress', 'awaiting_parts')
  ) then
    return 'duplicate';
  end if;

  insert into public.asset_work_orders (
    hospital_id,
    asset_id,
    work_order_type,
    priority,
    status,
    description,
    reporter_name,
    created_by
  ) values (
    v_hospital_id,
    p_asset_id,
    'fault',
    case when lower(trim(coalesce(p_priority, ''))) = 'urgent' then 'urgent' else 'normal' end,
    'open',
    trim(p_desc),
    nullif(left(trim(coalesce(p_reporter, '')), 80), ''),
    auth.uid()
  );

  return 'ok';
end;
$$;

-- These are the only intentionally public interfaces introduced by this migration.
-- No anonymous SELECT/INSERT/UPDATE grants are added to the underlying tables.
revoke all on function public.get_device_public_v2(text) from public, anon, authenticated;
revoke all on function public.get_asset_public(uuid) from public, anon, authenticated;
revoke all on function public.report_asset_fault(uuid, text, text, text) from public, anon, authenticated;

grant execute on function public.get_device_public_v2(text) to anon, authenticated;
grant execute on function public.get_asset_public(uuid) to anon, authenticated;
grant execute on function public.report_asset_fault(uuid, text, text, text) to anon, authenticated;
