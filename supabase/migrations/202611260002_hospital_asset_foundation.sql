-- Batch 1: additive hospital-wide asset foundation.
-- This migration is intentionally separate from 202611260001_central_hospital_modules.sql.
-- It does not drop, rename, truncate, or rewrite legacy equipment/fault/service records.
-- Apply only to a restored staging copy after reviewing the preflight and rollback notes.

begin;

create extension if not exists pgcrypto;

-- One-hospital deployment today; hospital_id keeps the data model ready for future expansion.
create table if not exists public.hospitals (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  country_code char(2) not null default 'NG',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.hospitals (name, slug)
values ('Central Hospital', 'central-hospital')
on conflict (slug) do nothing;

-- Department is the organisational owner (ward, clinic, unit, service).
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  name text not null,
  department_type text not null default 'department'
    check (department_type in ('ward','department','unit','service','other')),
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (hospital_id, name),
  unique (id, hospital_id)
);

-- Physical placement within a department: room, store, theatre room, etc.
create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  department_id uuid not null,
  name text not null,
  location_type text not null default 'area'
    check (location_type in ('room','area','store','theatre_room','office','other')),
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (department_id, hospital_id)
    references public.departments(id, hospital_id) on delete restrict,
  unique (department_id, name),
  unique (id, hospital_id)
);

create table if not exists public.asset_categories (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid references public.hospitals(id) on delete restrict,
  code text not null,
  name text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (hospital_id, code)
);

insert into public.asset_categories (hospital_id, code, name, description)
select h.id, v.code, v.name, v.description
from public.hospitals h
cross join (values
  ('MEDICAL','Medical equipment','Clinical diagnostic, monitoring and treatment equipment'),
  ('IMAGING','Imaging equipment','X-ray, ultrasound and other imaging systems'),
  ('LAB','Laboratory equipment','Laboratory analysers and supporting equipment'),
  ('ICT','ICT equipment','Computers, printers, networking and related devices'),
  ('FURNITURE','Furniture','Hospital and office furniture'),
  ('ELECTRICAL','Electrical infrastructure','Electrical distribution and fixed electrical assets'),
  ('POWER','Power infrastructure','Generators, UPS, solar and power systems'),
  ('FACILITY','Facilities and infrastructure','Building and facility assets'),
  ('OTHER','Other hospital assets','Assets not covered by another category')
) as v(code,name,description)
where h.slug = 'central-hospital'
on conflict (hospital_id, code) do nothing;

-- Canonical asset register. legacy_device_id preserves the exact existing devices.id value.
create table if not exists public.assets (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  asset_code text not null,
  name text not null,
  category_id uuid references public.asset_categories(id) on delete restrict,
  asset_kind text not null default 'equipment'
    check (asset_kind in ('equipment','accessory','furniture','ict','infrastructure','other')),
  manufacturer text,
  model text,
  serial_number text,
  department_id uuid,
  location_id uuid,
  operational_status text not null default 'in_service'
    check (operational_status in ('in_service','under_maintenance','out_of_service','in_storage','retired','missing')),
  physical_condition text
    check (physical_condition is null or physical_condition in ('excellent','good','fair','poor','unserviceable','unknown')),
  critical boolean not null default false,
  acquisition_date date,
  purchase_cost numeric(14,2) check (purchase_cost is null or purchase_cost >= 0),
  replacement_cost numeric(14,2) check (replacement_cost is null or replacement_cost >= 0),
  warranty_until date,
  vendor text,
  vendor_phone text,
  notes text,
  legacy_device_id text unique,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  retired_at timestamptz,
  foreign key (department_id, hospital_id)
    references public.departments(id, hospital_id) on delete restrict,
  foreign key (location_id, hospital_id)
    references public.locations(id, hospital_id) on delete restrict,
  unique (hospital_id, asset_code),
  unique (id, hospital_id)
);

create index if not exists assets_hospital_department_idx
  on public.assets(hospital_id, department_id);
create index if not exists assets_hospital_category_idx
  on public.assets(hospital_id, category_id);
create index if not exists assets_hospital_status_idx
  on public.assets(hospital_id, operational_status);
create index if not exists assets_name_search_idx
  on public.assets using gin (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(asset_code,'') || ' ' || coalesce(model,'') || ' ' || coalesce(serial_number,'')));

-- Accessories are individually traceable and can be linked to a parent asset.
create table if not exists public.asset_relationships (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  parent_asset_id uuid not null,
  child_asset_id uuid not null,
  relationship_type text not null default 'accessory'
    check (relationship_type in ('accessory','component','peripheral','paired_with')),
  notes text,
  created_at timestamptz not null default now(),
  foreign key (parent_asset_id, hospital_id) references public.assets(id, hospital_id) on delete restrict,
  foreign key (child_asset_id, hospital_id) references public.assets(id, hospital_id) on delete restrict,
  check (parent_asset_id <> child_asset_id),
  unique (parent_asset_id, child_asset_id, relationship_type)
);

create table if not exists public.asset_transfers (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  asset_id uuid not null,
  from_department_id uuid,
  to_department_id uuid not null,
  from_location_id uuid,
  to_location_id uuid,
  transfer_date timestamptz not null default now(),
  reason text,
  approved_by uuid references auth.users(id) on delete set null,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (asset_id, hospital_id) references public.assets(id, hospital_id) on delete restrict,
  foreign key (from_department_id, hospital_id) references public.departments(id, hospital_id) on delete restrict,
  foreign key (to_department_id, hospital_id) references public.departments(id, hospital_id) on delete restrict,
  foreign key (from_location_id, hospital_id) references public.locations(id, hospital_id) on delete restrict,
  foreign key (to_location_id, hospital_id) references public.locations(id, hospital_id) on delete restrict
);
create index if not exists asset_transfers_asset_date_idx
  on public.asset_transfers(asset_id, transfer_date desc);

create table if not exists public.asset_documents (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  asset_id uuid not null,
  document_type text not null
    check (document_type in ('manual','warranty','invoice','service_report','calibration_certificate','photo','other')),
  storage_path text not null,
  file_name text not null,
  content_type text,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (asset_id, hospital_id) references public.assets(id, hospital_id) on delete restrict
);
create index if not exists asset_documents_asset_idx on public.asset_documents(asset_id);

-- A generic audit trail for asset-register actions; application code will populate it in a later batch.
create table if not exists public.asset_audit_logs (
  id bigint generated always as identity primary key,
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  asset_id uuid,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now(),
  foreign key (asset_id, hospital_id) references public.assets(id, hospital_id) on delete restrict
);
create index if not exists asset_audit_logs_asset_date_idx
  on public.asset_audit_logs(asset_id, created_at desc);

-- Connect the existing ward directory to the hospital and normalised departments.
alter table public.hospital_locations
  add column if not exists hospital_id uuid references public.hospitals(id) on delete restrict,
  add column if not exists department_id uuid;

update public.hospital_locations hl
set hospital_id = h.id
from public.hospitals h
where h.slug = 'central-hospital' and hl.hospital_id is null;

insert into public.departments (hospital_id, name, department_type)
select h.id, hl.name,
       case when hl.location_type = 'ward' then 'ward' else 'department' end
from public.hospitals h
join public.hospital_locations hl on hl.hospital_id = h.id
where h.slug = 'central-hospital'
on conflict (hospital_id, name) do nothing;

-- Preserve legacy ward names not yet present in the eight initial directory entries.
insert into public.departments (hospital_id, name, department_type)
select h.id, trim(d.ward), 'other'
from public.hospitals h
cross join public.devices d
where h.slug = 'central-hospital'
  and nullif(trim(d.ward), '') is not null
on conflict (hospital_id, name) do nothing;

update public.hospital_locations hl
set department_id = d.id
from public.departments d
where d.hospital_id = hl.hospital_id and d.name = hl.name
  and hl.department_id is null;

-- Link the old directory rows to the new canonical department records.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hospital_locations_department_hospital_fk'
      and conrelid = 'public.hospital_locations'::regclass
  ) then
    alter table public.hospital_locations
      add constraint hospital_locations_department_hospital_fk
      foreign key (department_id, hospital_id)
      references public.departments(id, hospital_id) on delete restrict;
  end if;
end $$;

create index if not exists hospital_locations_hospital_department_idx
  on public.hospital_locations(hospital_id, department_id);

-- Copy current device records into the canonical register without changing the source rows.
-- The original devices table remains the compatibility source until the application is migrated.
insert into public.assets (
  hospital_id, asset_code, name, asset_kind, model, serial_number,
  department_id, critical, replacement_cost, warranty_until, vendor, vendor_phone,
  legacy_device_id
)
select
  h.id,
  d.id::text,
  d.name,
  'equipment',
  nullif(d.model,''),
  nullif(d.serial,''),
  dep.id,
  coalesce(d.critical,false),
  d.replacement_cost,
  d.warranty_until,
  nullif(d.vendor,''),
  nullif(d.vendor_phone,''),
  d.id::text
from public.hospitals h
cross join public.devices d
left join public.departments dep
  on dep.hospital_id = h.id and dep.name = nullif(trim(d.ward),'')
where h.slug = 'central-hospital'
on conflict (legacy_device_id) do nothing;

-- Keep generator profiles specialised while allowing each generator to have a central asset identity.
alter table public.generators
  add column if not exists hospital_id uuid references public.hospitals(id) on delete restrict,
  add column if not exists asset_id uuid;

update public.generators g
set hospital_id = h.id
from public.hospitals h
where h.slug = 'central-hospital' and g.hospital_id is null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'generators_asset_hospital_fk'
      and conrelid = 'public.generators'::regclass
  ) then
    alter table public.generators
      add constraint generators_asset_hospital_fk
      foreign key (asset_id, hospital_id)
      references public.assets(id, hospital_id) on delete restrict;
  end if;
end $$;

create index if not exists generators_hospital_asset_idx
  on public.generators(hospital_id, asset_id);

-- Initial row-level security: authenticated staff can read; only central Biomedical/admin
-- roles can create or change the foundation in this first rollout batch.
alter table public.hospitals enable row level security;
alter table public.departments enable row level security;
alter table public.locations enable row level security;
alter table public.asset_categories enable row level security;
alter table public.assets enable row level security;
alter table public.asset_relationships enable row level security;
alter table public.asset_transfers enable row level security;
alter table public.asset_documents enable row level security;
alter table public.asset_audit_logs enable row level security;

drop policy if exists hospitals_read_authenticated on public.hospitals;
create policy hospitals_read_authenticated on public.hospitals
  for select to authenticated using (true);
drop policy if exists hospitals_manage_biomedical on public.hospitals;
create policy hospitals_manage_biomedical on public.hospitals
  for all to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

drop policy if exists departments_read_authenticated on public.departments;
create policy departments_read_authenticated on public.departments
  for select to authenticated using (true);
drop policy if exists departments_manage_biomedical on public.departments;
create policy departments_manage_biomedical on public.departments
  for all to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

drop policy if exists locations_read_authenticated on public.locations;
create policy locations_read_authenticated on public.locations
  for select to authenticated using (true);
drop policy if exists locations_manage_biomedical on public.locations;
create policy locations_manage_biomedical on public.locations
  for all to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

drop policy if exists asset_categories_read_authenticated on public.asset_categories;
create policy asset_categories_read_authenticated on public.asset_categories
  for select to authenticated using (true);
drop policy if exists asset_categories_manage_biomedical on public.asset_categories;
create policy asset_categories_manage_biomedical on public.asset_categories
  for all to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

drop policy if exists assets_read_authenticated on public.assets;
create policy assets_read_authenticated on public.assets
  for select to authenticated using (true);
drop policy if exists assets_manage_biomedical on public.assets;
create policy assets_manage_biomedical on public.assets
  for all to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

drop policy if exists asset_relationships_read_authenticated on public.asset_relationships;
create policy asset_relationships_read_authenticated on public.asset_relationships
  for select to authenticated using (true);
drop policy if exists asset_relationships_manage_biomedical on public.asset_relationships;
create policy asset_relationships_manage_biomedical on public.asset_relationships
  for all to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

drop policy if exists asset_transfers_read_authenticated on public.asset_transfers;
create policy asset_transfers_read_authenticated on public.asset_transfers
  for select to authenticated using (true);
drop policy if exists asset_transfers_manage_biomedical on public.asset_transfers;
create policy asset_transfers_manage_biomedical on public.asset_transfers
  for all to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

drop policy if exists asset_documents_read_authenticated on public.asset_documents;
create policy asset_documents_read_authenticated on public.asset_documents
  for select to authenticated using (true);
drop policy if exists asset_documents_manage_biomedical on public.asset_documents;
create policy asset_documents_manage_biomedical on public.asset_documents
  for all to authenticated using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

drop policy if exists asset_audit_logs_read_biomedical on public.asset_audit_logs;
create policy asset_audit_logs_read_biomedical on public.asset_audit_logs
  for select to authenticated using (public.has_app_role(array['admin','biomedical']));
drop policy if exists asset_audit_logs_insert_authenticated on public.asset_audit_logs;
create policy asset_audit_logs_insert_authenticated on public.asset_audit_logs
  for insert to authenticated with check (actor_id = auth.uid());

-- Explicit Data API privileges for current Supabase defaults; RLS remains the row boundary.
revoke all on public.hospitals, public.departments, public.locations,
  public.asset_categories, public.assets, public.asset_relationships,
  public.asset_transfers, public.asset_documents, public.asset_audit_logs from anon;
grant select, insert, update, delete on public.hospitals, public.departments,
  public.locations, public.asset_categories, public.assets,
  public.asset_relationships, public.asset_transfers, public.asset_documents to authenticated;
grant select on public.asset_audit_logs to authenticated;
commit;

-- Verification queries to run on staging after applying:
-- select count(*) as legacy_devices from public.devices;
-- select count(*) as copied_assets from public.assets where legacy_device_id is not null;
-- select count(*) as unmapped_legacy_devices
-- from public.devices d
-- left join public.assets a on a.legacy_device_id = d.id::text
-- where a.id is null;
-- select d.id, d.name, d.ward
-- from public.devices d
-- join public.assets a on a.legacy_device_id = d.id::text
-- join public.departments dep on dep.id = a.department_id
-- where coalesce(trim(d.ward),'') <> dep.name;
