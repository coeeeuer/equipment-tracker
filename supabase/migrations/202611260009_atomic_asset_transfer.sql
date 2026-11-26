-- Batch 9: atomic canonical asset transfer workflow.
-- Transfers update the asset's department/location and append immutable transfer history
-- in one database transaction. This function runs with caller privileges so RLS applies.

create or replace function public.transfer_asset(
  p_asset_id uuid,
  p_to_department_id uuid,
  p_to_location_id uuid default null,
  p_transfer_date timestamptz default now(),
  p_reason text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_hospital_id uuid;
  v_from_department_id uuid;
  v_from_location_id uuid;
  v_transfer_id uuid := gen_random_uuid();
begin
  if not public.has_app_role(array['admin','biomedical']) then
    raise exception 'Only hospital administrators and Biomedical Engineering may transfer canonical assets';
  end if;

  select a.hospital_id, a.department_id, a.location_id
    into v_hospital_id, v_from_department_id, v_from_location_id
  from public.assets a
  where a.id = p_asset_id
  for update;

  if v_hospital_id is null then
    raise exception 'Asset not found or access denied';
  end if;

  if p_to_department_id is null or not exists (
    select 1 from public.departments d
    where d.id = p_to_department_id
      and d.hospital_id = v_hospital_id
      and d.active = true
  ) then
    raise exception 'Destination department is invalid or inactive';
  end if;

  if p_to_location_id is not null and not exists (
    select 1 from public.locations l
    where l.id = p_to_location_id
      and l.hospital_id = v_hospital_id
      and l.department_id = p_to_department_id
      and l.active = true
  ) then
    raise exception 'Destination room must belong to the destination department';
  end if;

  insert into public.asset_transfers (
    id, hospital_id, asset_id, from_department_id, to_department_id,
    from_location_id, to_location_id, transfer_date, reason,
    approved_by, recorded_by
  ) values (
    v_transfer_id, v_hospital_id, p_asset_id, v_from_department_id,
    p_to_department_id, v_from_location_id, p_to_location_id,
    coalesce(p_transfer_date, now()), nullif(trim(p_reason), ''),
    auth.uid(), auth.uid()
  );

  update public.assets
  set department_id = p_to_department_id,
      location_id = p_to_location_id
  where id = p_asset_id;

  return v_transfer_id;
end;
$$;

revoke all on function public.transfer_asset(uuid,uuid,uuid,timestamptz,text) from public, anon;
grant execute on function public.transfer_asset(uuid,uuid,uuid,timestamptz,text) to authenticated;
