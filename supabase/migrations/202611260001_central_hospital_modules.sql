-- Central Hospital rollout: locations, generator assets and generator records.
-- Apply in Supabase SQL Editor AFTER reviewing the access-control bootstrap section below.
-- This migration deliberately does not alter existing devices/faults/services/audits tables.

create extension if not exists pgcrypto;

-- Application roles. A hospital administrator must assign the first admin manually
-- using the Supabase Auth user's UUID (see docs/central-hospital-rollout.md).
create table if not exists public.app_user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','biomedical','viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.app_user_roles where user_id = auth.uid()
$$;

create or replace function public.has_app_role(allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_app_role() = any(allowed_roles), false)
$$;

alter table public.app_user_roles enable row level security;
drop policy if exists "Users can read own role" on public.app_user_roles;
create policy "Users can read own role" on public.app_user_roles
  for select to authenticated using (user_id = auth.uid() or public.has_app_role(array['admin']));
drop policy if exists "Admins manage app roles" on public.app_user_roles;
create policy "Admins manage app roles" on public.app_user_roles
  for all to authenticated using (public.has_app_role(array['admin']))
  with check (public.has_app_role(array['admin']));

-- Ward/department directory. Existing devices.ward remains text for backward compatibility.
create table if not exists public.hospital_locations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  location_type text not null check (location_type in ('ward','department')),
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.hospital_locations enable row level security;
drop policy if exists "Authenticated users read hospital locations" on public.hospital_locations;
create policy "Authenticated users read hospital locations" on public.hospital_locations
  for select to authenticated using (true);
drop policy if exists "Authorised staff manage hospital locations" on public.hospital_locations;
create policy "Authorised staff manage hospital locations" on public.hospital_locations
  for all to authenticated
  using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

insert into public.hospital_locations (name, location_type) values
  ('Maternity Ward','ward'),
  ('Eye Clinic','department'),
  ('Female Ward','ward'),
  ('Amenity Ward','ward'),
  ('Male Ophthalmic Ward','ward'),
  ('Operating Theatre','department'),
  ('X-Ray / Ultrasound Unit','department'),
  ('Accident and Emergency','department')
on conflict (name) do nothing;

-- Generator assets are intentionally separate from medical devices.
create table if not exists public.generators (
  id uuid primary key default gen_random_uuid(),
  asset_code text not null unique,
  name text not null,
  manufacturer text,
  model text,
  serial_number text,
  manufacture_date date,
  installation_date date,
  location text,
  fuel_type text,
  engine_manufacturer text,
  engine_model text,
  engine_serial_number text,
  alternator_manufacturer text,
  alternator_model text,
  controller_model text,
  standby_kva numeric(10,2),
  standby_kw numeric(10,2),
  prime_kva numeric(10,2),
  prime_kw numeric(10,2),
  rated_voltage text,
  phases smallint,
  frequency_hz numeric(6,2),
  power_factor numeric(4,3),
  rated_rpm integer,
  standby_current_a numeric(10,2),
  prime_current_a numeric(10,2),
  ambient_temperature_c numeric(6,2),
  fuel_tank_capacity_l numeric(10,2),
  hour_meter_reading numeric(12,1),
  hour_meter_recorded_at timestamptz,
  operational_status text not null default 'unknown'
    check (operational_status in ('unknown','operational','under_maintenance','out_of_service','retired')),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
create index if not exists generators_status_idx on public.generators(operational_status);
alter table public.generators enable row level security;
drop policy if exists "Authenticated users read generators" on public.generators;
create policy "Authenticated users read generators" on public.generators
  for select to authenticated using (true);
drop policy if exists "Authorised staff insert generators" on public.generators;
create policy "Authorised staff insert generators" on public.generators
  for insert to authenticated with check (public.has_app_role(array['admin','biomedical']));
drop policy if exists "Authorised staff update generators" on public.generators;
create policy "Authorised staff update generators" on public.generators
  for update to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));
drop policy if exists "Admins delete generators" on public.generators;
create policy "Admins delete generators" on public.generators
  for delete to authenticated using (public.has_app_role(array['admin']));

-- Basic diesel/refuelling log. Consumption is not inferred from a fill-up entry.
create table if not exists public.generator_fuel_logs (
  id uuid primary key default gen_random_uuid(),
  generator_id uuid not null references public.generators(id) on delete restrict,
  refuelled_at timestamptz not null default now(),
  quantity_litres numeric(10,2) not null check (quantity_litres > 0),
  amount_paid_ngn numeric(14,2) check (amount_paid_ngn is null or amount_paid_ngn >= 0),
  hour_meter_reading numeric(12,1) check (hour_meter_reading is null or hour_meter_reading >= 0),
  recorded_by uuid references auth.users(id) on delete set null,
  supplier_or_source text,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists generator_fuel_logs_generator_date_idx
  on public.generator_fuel_logs(generator_id, refuelled_at desc);
alter table public.generator_fuel_logs enable row level security;
drop policy if exists "Authenticated users read generator fuel logs" on public.generator_fuel_logs;
create policy "Authenticated users read generator fuel logs" on public.generator_fuel_logs
  for select to authenticated using (true);
drop policy if exists "Authorised staff add generator fuel logs" on public.generator_fuel_logs;
create policy "Authorised staff add generator fuel logs" on public.generator_fuel_logs
  for insert to authenticated with check (public.has_app_role(array['admin','biomedical']));
drop policy if exists "Authorised staff update generator fuel logs" on public.generator_fuel_logs;
create policy "Authorised staff update generator fuel logs" on public.generator_fuel_logs
  for update to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));
drop policy if exists "Admins delete generator fuel logs" on public.generator_fuel_logs;
create policy "Admins delete generator fuel logs" on public.generator_fuel_logs
  for delete to authenticated using (public.has_app_role(array['admin']));

-- Generator-specific maintenance/service history.
create table if not exists public.generator_maintenance (
  id uuid primary key default gen_random_uuid(),
  generator_id uuid not null references public.generators(id) on delete restrict,
  service_date date not null default current_date,
  hour_meter_reading numeric(12,1) check (hour_meter_reading is null or hour_meter_reading >= 0),
  service_type text not null,
  work_performed text not null,
  parts_used text,
  cost_ngn numeric(14,2) check (cost_ngn is null or cost_ngn >= 0),
  next_due_date date,
  next_due_hours numeric(12,1),
  performed_by text,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists generator_maintenance_generator_date_idx
  on public.generator_maintenance(generator_id, service_date desc);
alter table public.generator_maintenance enable row level security;
drop policy if exists "Authenticated users read generator maintenance" on public.generator_maintenance;
create policy "Authenticated users read generator maintenance" on public.generator_maintenance
  for select to authenticated using (true);
drop policy if exists "Authorised staff add generator maintenance" on public.generator_maintenance;
create policy "Authorised staff add generator maintenance" on public.generator_maintenance
  for insert to authenticated with check (public.has_app_role(array['admin','biomedical']));
drop policy if exists "Authorised staff update generator maintenance" on public.generator_maintenance;
create policy "Authorised staff update generator maintenance" on public.generator_maintenance
  for update to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));
drop policy if exists "Admins delete generator maintenance" on public.generator_maintenance;
create policy "Admins delete generator maintenance" on public.generator_maintenance
  for delete to authenticated using (public.has_app_role(array['admin']));

-- Generator breakdowns are kept separate from medical-device faults.
create table if not exists public.generator_faults (
  id uuid primary key default gen_random_uuid(),
  generator_id uuid not null references public.generators(id) on delete restrict,
  reported_at timestamptz not null default now(),
  description text not null,
  priority text not null default 'Normal' check (priority in ('Normal','Urgent')),
  status text not null default 'Reported'
    check (status in ('Reported','In repair','Awaiting parts','Resolved')),
  reported_by text,
  resolved_at timestamptz,
  action_taken text,
  repaired_by text,
  cost_ngn numeric(14,2) check (cost_ngn is null or cost_ngn >= 0),
  created_at timestamptz not null default now()
);
create index if not exists generator_faults_generator_date_idx
  on public.generator_faults(generator_id, reported_at desc);
alter table public.generator_faults enable row level security;
drop policy if exists "Authenticated users read generator faults" on public.generator_faults;
create policy "Authenticated users read generator faults" on public.generator_faults
  for select to authenticated using (true);
drop policy if exists "Authorised staff add generator faults" on public.generator_faults;
create policy "Authorised staff add generator faults" on public.generator_faults
  for insert to authenticated with check (public.has_app_role(array['admin','biomedical']));
drop policy if exists "Authorised staff update generator faults" on public.generator_faults;
create policy "Authorised staff update generator faults" on public.generator_faults
  for update to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));
drop policy if exists "Admins delete generator faults" on public.generator_faults;
create policy "Admins delete generator faults" on public.generator_faults
  for delete to authenticated using (public.has_app_role(array['admin']));

-- Bootstrap: after applying this migration, find the intended administrator's UUID
-- in Supabase Authentication > Users, then run:
-- insert into public.app_user_roles (user_id, role)
-- values ('REPLACE-WITH-AUTH-USER-UUID', 'admin')
-- on conflict (user_id) do update set role = excluded.role, updated_at = now();
