-- Batch 6: department membership and least-privilege canonical asset access.
-- Prerequisites: migrations 001 and 002.
-- This adds database enforcement. Do not assign department roles until the UI/workflow
-- and staging permission tests have been completed.

begin;

alter table public.app_user_roles
  drop constraint if exists app_user_roles_role_check;
alter table public.app_user_roles
  add constraint app_user_roles_role_check
  check (role in ('admin','biomedical','department_officer','maintenance','viewer'));

create table if not exists public.department_memberships (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  department_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  membership_role text not null
    check (membership_role in ('asset_officer','maintenance')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  unique (hospital_id, department_id, user_id),
  foreign key (department_id, hospital_id)
    references public.departments(id, hospital_id) on delete restrict
);

create index if not exists department_memberships_user_active_idx
  on public.department_memberships(user_id, active, department_id);

alter table public.department_memberships enable row level security;

drop policy if exists department_memberships_read_scoped on public.department_memberships;
create policy department_memberships_read_scoped on public.department_memberships
  for select to authenticated
  using (user_id = auth.uid() or public.has_app_role(array['admin','biomedical']));

drop policy if exists department_memberships_manage_biomedical on public.department_memberships;
create policy department_memberships_manage_biomedical on public.department_memberships
  for all to authenticated
  using (public.has_app_role(array['admin','biomedical']))
  with check (public.has_app_role(array['admin','biomedical']));

create or replace function public.is_department_member(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.department_memberships m
    where m.user_id = auth.uid()
      and m.department_id = p_department_id
      and m.active = true
  )
$$;

create or replace function public.is_department_asset_officer(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1
    from public.department_memberships m
    where m.user_id = auth.uid()
      and m.department_id = p_department_id
      and m.membership_role = 'asset_officer'
      and m.active = true
  )
$;

create or replace function public.can_view_department(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_app_role(array['admin','biomedical','viewer'])
      or public.is_department_member(p_department_id)
$$;

-- Replace the initial broad canonical-asset read policy with scoped access.
drop policy if exists assets_read_authenticated on public.assets;
drop policy if exists assets_read_scoped on public.assets;
create policy assets_read_scoped on public.assets
  for select to authenticated
  using (public.can_view_department(department_id));

-- Department asset officers may create/update assets only in their assigned departments.
-- Maintenance and department-viewer memberships are intentionally read-only.
drop policy if exists assets_department_officer_insert on public.assets;
create policy assets_department_officer_insert on public.assets
  for insert to authenticated
  with check (
    public.has_app_role(array['department_officer'])
    and public.is_department_asset_officer(department_id)
  );

drop policy if exists assets_department_officer_update on public.assets;
create policy assets_department_officer_update on public.assets
  for update to authenticated
  using (
    public.has_app_role(array['department_officer'])
    and public.is_department_member(department_id)
  )
  with check (
    public.has_app_role(array['department_officer'])
    and public.is_department_member(department_id)
  );

-- Documents follow the access rights of their parent asset.
drop policy if exists asset_documents_read_authenticated on public.asset_documents;
drop policy if exists asset_documents_read_scoped on public.asset_documents;
create policy asset_documents_read_scoped on public.asset_documents
  for select to authenticated
  using (
    exists (
      select 1 from public.assets a
      where a.id = asset_documents.asset_id
        and public.can_view_department(a.department_id)
    )
  );

drop policy if exists asset_documents_department_officer_insert on public.asset_documents;
create policy asset_documents_department_officer_insert on public.asset_documents
  for insert to authenticated
  with check (
    public.has_app_role(array['department_officer'])
    and exists (
      select 1 from public.assets a
      where a.id = asset_documents.asset_id
        and public.is_department_asset_officer(a.department_id)
    )
  );

drop policy if exists asset_documents_department_officer_update on public.asset_documents;
create policy asset_documents_department_officer_update on public.asset_documents
  for update to authenticated
  using (
    public.has_app_role(array['department_officer'])
    and exists (
      select 1 from public.assets a
      where a.id = asset_documents.asset_id
        and public.is_department_member(a.department_id)
    )
  )
  with check (
    public.has_app_role(array['department_officer'])
    and exists (
      select 1 from public.assets a
      where a.id = asset_documents.asset_id
        and public.is_department_member(a.department_id)
    )
  );

-- Relationship visibility requires access to both linked assets.
drop policy if exists asset_relationships_read_authenticated on public.asset_relationships;
drop policy if exists asset_relationships_read_scoped on public.asset_relationships;
create policy asset_relationships_read_scoped on public.asset_relationships
  for select to authenticated
  using (
    exists (
      select 1 from public.assets p
      join public.assets c on c.id = asset_relationships.child_asset_id
      where p.id = asset_relationships.parent_asset_id
        and public.can_view_department(p.department_id)
        and public.can_view_department(c.department_id)
    )
  );

-- Transfer history is visible to central roles and to users assigned to either
-- the source or destination department.
drop policy if exists asset_transfers_read_authenticated on public.asset_transfers;
drop policy if exists asset_transfers_read_scoped on public.asset_transfers;
create policy asset_transfers_read_scoped on public.asset_transfers
  for select to authenticated
  using (
    public.can_view_department(from_department_id)
    or public.can_view_department(to_department_id)
  );

-- Keep physical placement consistent with the asset's organisational department.
create or replace function public.enforce_asset_location_department()
returns trigger
language plpgsql
set search_path = ''
as $
declare
  v_location_department uuid;
begin
  if new.location_id is null then
    return new;
  end if;

  select l.department_id
    into v_location_department
  from public.locations l
  where l.id = new.location_id
    and l.hospital_id = new.hospital_id;

  if v_location_department is null or v_location_department is distinct from new.department_id then
    raise exception 'Asset location must belong to the asset department';
  end if;
  return new;
end;
$;

drop trigger if exists assets_validate_location_department on public.assets;
create trigger assets_validate_location_department
before insert or update of hospital_id, department_id, location_id on public.assets
for each row execute function public.enforce_asset_location_department();

-- A maintenance user may see the assets in their assigned departments but cannot
-- edit the canonical identity, ownership, department or audit records.
commit;

-- Staging permission tests:
-- admin/biomedical/viewer: can read all hospital assets.
-- department_officer: can read and create/update only assets in active assigned departments.
-- maintenance: can read only assets in active assigned departments; cannot write assets.
-- no-role user: cannot read the canonical asset register.
-- no user can mutate department_memberships unless admin/biomedical.


-- RLS helper functions are callable only by signed-in users. These functions
-- answer questions about the caller's own role/membership and never accept a user ID.
revoke all on function public.is_department_member(uuid) from public, anon;
revoke all on function public.is_department_asset_officer(uuid) from public, anon;
revoke all on function public.can_view_department(uuid) from public, anon;
grant execute on function public.is_department_member(uuid) to authenticated;
grant execute on function public.is_department_asset_officer(uuid) to authenticated;
grant execute on function public.can_view_department(uuid) to authenticated;

-- Central module directory and generator data are visible only to central roles.
drop policy if exists "Authenticated users read hospital locations" on public.hospital_locations;
create policy "Hospital roles read hospital locations" on public.hospital_locations
  for select to authenticated
  using (public.has_app_role(array['admin','biomedical','viewer','department_officer','maintenance']));

drop policy if exists "Authenticated users read generators" on public.generators;
create policy "Central roles read generators" on public.generators
  for select to authenticated
  using (public.has_app_role(array['admin','biomedical','viewer']));

drop policy if exists "Authenticated users read generator fuel logs" on public.generator_fuel_logs;
create policy "Central roles read generator fuel logs" on public.generator_fuel_logs
  for select to authenticated
  using (public.has_app_role(array['admin','biomedical','viewer']));

drop policy if exists "Authenticated users read generator maintenance" on public.generator_maintenance;
create policy "Central roles read generator maintenance" on public.generator_maintenance
  for select to authenticated
  using (public.has_app_role(array['admin','biomedical','viewer']));

drop policy if exists "Authenticated users read generator faults" on public.generator_faults;
create policy "Central roles read generator faults" on public.generator_faults
  for select to authenticated
  using (public.has_app_role(array['admin','biomedical','viewer']));
