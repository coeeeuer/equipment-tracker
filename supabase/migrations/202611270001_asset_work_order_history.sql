-- Batch 10: unified work-order, fault and preventive-maintenance history for every canonical asset.
-- Additive only. Does not alter or delete legacy faults/services records.
-- Prerequisites: migrations 001, 002 and 005.

create table if not exists public.asset_work_orders (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  asset_id uuid not null,
  work_order_type text not null
    check (work_order_type in ('fault','repair','preventive_maintenance','calibration','safety_test','inspection','other')),
  priority text not null default 'normal'
    check (priority in ('low','normal','high','urgent')),
  status text not null default 'open'
    check (status in ('open','in_progress','awaiting_parts','completed','cancelled')),
  reported_at timestamptz not null default now(),
  scheduled_for date,
  completed_at timestamptz,
  description text not null check (length(trim(description)) > 0),
  action_taken text,
  parts_used text,
  performed_by text,
  vendor text,
  cost_ngn numeric(14,2) check (cost_ngn is null or cost_ngn >= 0),
  next_due_date date,
  next_due_hours numeric(12,1) check (next_due_hours is null or next_due_hours >= 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  foreign key (asset_id, hospital_id)
    references public.assets(id, hospital_id) on delete restrict,
  check (completed_at is null or completed_at >= reported_at)
);

create index if not exists asset_work_orders_asset_date_idx
  on public.asset_work_orders(asset_id, reported_at desc);
create index if not exists asset_work_orders_hospital_status_idx
  on public.asset_work_orders(hospital_id, status, reported_at desc);
create index if not exists asset_work_orders_due_idx
  on public.asset_work_orders(hospital_id, next_due_date)
  where status = 'completed' and next_due_date is not null;

alter table public.asset_work_orders enable row level security;

drop policy if exists asset_work_orders_read_scoped on public.asset_work_orders;
create policy asset_work_orders_read_scoped on public.asset_work_orders
  for select to authenticated
  using (
    exists (
      select 1 from public.assets a
      where a.id = asset_work_orders.asset_id
        and a.hospital_id = asset_work_orders.hospital_id
        and public.can_view_department(a.department_id)
    )
  );

-- Until the hospital confirms its staff permissions, only central admin/Biomedical
-- roles may create or update canonical work orders. Department and maintenance-role
-- write access is deliberately deferred; it must not be inferred from this UI.
drop policy if exists asset_work_orders_insert_central on public.asset_work_orders;
create policy asset_work_orders_insert_central on public.asset_work_orders
  for insert to authenticated
  with check (
    public.has_app_role(array['admin','biomedical'])
    and created_by = auth.uid()
    and exists (
      select 1 from public.assets a
      where a.id = asset_work_orders.asset_id
        and a.hospital_id = asset_work_orders.hospital_id
        and public.can_view_department(a.department_id)
    )
  );

drop policy if exists asset_work_orders_update_central on public.asset_work_orders;
create policy asset_work_orders_update_central on public.asset_work_orders
  for update to authenticated
  using (public.has_app_role(array['admin','biomedical']))
  with check (
    public.has_app_role(array['admin','biomedical'])
    and exists (
      select 1 from public.assets a
      where a.id = asset_work_orders.asset_id
        and a.hospital_id = asset_work_orders.hospital_id
        and public.can_view_department(a.department_id)
    )
  );

grant select, insert, update on public.asset_work_orders to authenticated;
revoke all on public.asset_work_orders from anon;

create or replace function public.set_asset_work_order_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if new.status = 'completed' and new.completed_at is null then
    new.completed_at := now();
  elsif new.status <> 'completed' then
    new.completed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists asset_work_orders_set_updated_at on public.asset_work_orders;
create trigger asset_work_orders_set_updated_at
before update on public.asset_work_orders
for each row execute function public.set_asset_work_order_updated_at();

revoke all on function public.set_asset_work_order_updated_at() from public, anon, authenticated;

-- Verification checklist (run on a restored staging database):
-- 1. Confirm existing faults/services counts are unchanged.
-- 2. Create one work order of each supported type and verify asset history ordering.
-- 3. Confirm a viewer can read but cannot insert/update.
-- 4. Confirm no-role and anon users cannot read or write.
-- 5. Confirm maintenance/department roles cannot write until HOD-approved permissions are implemented.
-- 6. Confirm a completed work order receives completed_at and changing status clears it.
