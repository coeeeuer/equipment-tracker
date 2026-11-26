-- Batch 4: immutable audit trail for canonical asset changes and transfers.
-- Prerequisite: 202611260002_hospital_asset_foundation.sql
-- Additive. Existing legacy audits are not altered.

begin;

-- Audit entries are written by the SECURITY DEFINER triggers, not by browser clients.
drop policy if exists asset_audit_logs_insert_authenticated on public.asset_audit_logs;

create or replace function public.set_asset_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.audit_canonical_asset_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    insert into public.asset_audit_logs(hospital_id, asset_id, actor_id, action, before_data, after_data)
    values (new.hospital_id, new.id, v_actor, 'created', null, to_jsonb(new));
    return new;
  elsif tg_op = 'UPDATE' then
    if to_jsonb(new) is distinct from to_jsonb(old) then
      insert into public.asset_audit_logs(hospital_id, asset_id, actor_id, action, before_data, after_data)
      values (new.hospital_id, new.id, v_actor, 'updated', to_jsonb(old), to_jsonb(new));
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    -- Keep a durable deletion event without a foreign key to the deleted asset row.
    insert into public.asset_audit_logs(hospital_id, asset_id, actor_id, action, before_data, after_data)
    values (old.hospital_id, null, v_actor, 'deleted', to_jsonb(old), null);
    return old;
  end if;
  return null;
end;
$$;

create or replace function public.audit_asset_transfer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.asset_audit_logs(hospital_id, asset_id, actor_id, action, before_data, after_data)
  values (
    new.hospital_id,
    new.asset_id,
    auth.uid(),
    'transfer_recorded',
    jsonb_build_object(
      'from_department_id', new.from_department_id,
      'from_location_id', new.from_location_id
    ),
    jsonb_build_object(
      'to_department_id', new.to_department_id,
      'to_location_id', new.to_location_id,
      'transfer_date', new.transfer_date,
      'reason', new.reason,
      'approved_by', new.approved_by
    )
  );
  return new;
end;
$$;

drop trigger if exists assets_set_updated_at on public.assets;
create trigger assets_set_updated_at
before update on public.assets
for each row execute function public.set_asset_updated_at();

drop trigger if exists assets_audit_changes on public.assets;
create trigger assets_audit_changes
after insert or update or delete on public.assets
for each row execute function public.audit_canonical_asset_change();

drop trigger if exists asset_transfers_audit_insert on public.asset_transfers;
create trigger asset_transfers_audit_insert
after insert on public.asset_transfers
for each row execute function public.audit_asset_transfer();

-- Authenticated users may read audit rows only if they hold the central oversight role.
-- No authenticated update/delete policy is created for audit rows.

commit;

-- Staging verification:
-- insert/update a test asset and confirm created/updated rows appear in asset_audit_logs.
-- insert a test transfer and confirm transfer_recorded appears.
-- verify an ordinary viewer cannot read or mutate the audit log.
-- verify asset changes roll back if the audit trigger fails (same transaction).
