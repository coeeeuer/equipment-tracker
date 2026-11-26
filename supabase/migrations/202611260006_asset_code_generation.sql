-- Batch 7: concurrency-safe canonical asset code generation.
-- Prerequisite: 202611260002_hospital_asset_foundation.sql
-- Existing legacy and generator asset codes are preserved; only blank/new codes are generated.

begin;

create table if not exists public.asset_code_counters (
  hospital_id uuid primary key references public.hospitals(id) on delete restrict,
  prefix text not null,
  next_value bigint not null default 0 check (next_value >= 0),
  updated_at timestamptz not null default now()
);

insert into public.asset_code_counters(hospital_id, prefix, next_value)
select id,
       case when position('-' in slug) > 0 then upper(left(split_part(slug, '-', 1), 1) || left(split_part(slug, '-', 2), 1)) else upper(left(regexp_replace(slug, '[^A-Za-z0-9]', '', 'g'), 2)) end,
       0
from public.hospitals
on conflict (hospital_id) do nothing;

alter table public.asset_code_counters enable row level security;
revoke all on public.asset_code_counters from anon, authenticated;

create or replace function public.assign_asset_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prefix text;
  v_number bigint;
  v_candidate text;
begin
  if nullif(trim(new.asset_code), '') is not null then
    return new;
  end if;

  loop
    insert into public.asset_code_counters(hospital_id, prefix, next_value)
    select new.hospital_id,
           case when position('-' in h.slug) > 0 then upper(left(split_part(h.slug, '-', 1), 1) || left(split_part(h.slug, '-', 2), 1)) else upper(left(regexp_replace(h.slug, '[^A-Za-z0-9]', '', 'g'), 2)) end,
           1
    from public.hospitals h
    where h.id = new.hospital_id
    on conflict (hospital_id) do update
      set next_value = public.asset_code_counters.next_value + 1,
          updated_at = now()
    returning prefix, next_value into v_prefix, v_number;

    if v_prefix is null or v_number is null then
      raise exception 'Cannot generate asset code: hospital % does not exist', new.hospital_id;
    end if;

    v_candidate := v_prefix || '-' || lpad(v_number::text, 6, '0');
    exit when not exists (
      select 1 from public.assets a
      where a.hospital_id = new.hospital_id
        and a.asset_code = v_candidate
    );
  end loop;

  new.asset_code := v_candidate;
  return new;
end;
$$;

drop trigger if exists assets_assign_asset_code on public.assets;
create trigger assets_assign_asset_code
before insert on public.assets
for each row execute function public.assign_asset_code();

commit;

-- Staging verification:
-- Insert several test assets with asset_code omitted and confirm unique CH-000001-style codes.
-- Run concurrent inserts and confirm no duplicate code is produced.
-- Confirm existing EQ-... and GEN-... codes remain unchanged.
