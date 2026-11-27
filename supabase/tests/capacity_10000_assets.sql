-- 10,000-asset capacity smoke test.
-- Run ONLY on an isolated staging database after migrations 001-011.
-- The entire test is rolled back. Do not run against production.
-- Use the EXPLAIN ANALYZE output to record actual execution times and plans.

begin;

create temporary table _capacity_test_ids (
  hospital_id uuid not null,
  department_id uuid not null,
  category_id uuid not null
) on commit drop;

with h as (
  insert into public.hospitals(name,slug,country_code)
  values ('Capacity Test (ROLLBACK ONLY)','capacity-test-rollback','NG')
  returning id
), d as (
  insert into public.departments(hospital_id,name,department_type)
  select id,'Capacity Test Ward (ROLLBACK ONLY)','ward' from h
  returning id,hospital_id
), c as (
  insert into public.asset_categories(hospital_id,code,name)
  select id,'CAPACITY_TEST','Capacity Test Category' from h
  returning id,hospital_id
)
insert into _capacity_test_ids(hospital_id,department_id,category_id)
select d.hospital_id,d.id,c.id from d join c using(hospital_id);

insert into public.assets(
  hospital_id,asset_code,name,category_id,asset_kind,model,serial_number,
  department_id,operational_status,physical_condition
)
select t.hospital_id,null,
       'Capacity Test Asset '||lpad(g.n::text,5,'0'),
       t.category_id,
       case when g.n%4=0 then 'accessory' else 'equipment' end,
       'TEST-MODEL-'||(g.n%120),
       'CAP-SN-'||g.n,
       t.department_id,
       case when g.n%10=0 then 'under_maintenance' else 'in_service' end,
       case when g.n%7=0 then 'fair' else 'good' end
from _capacity_test_ids t
cross join generate_series(1,10000) as g(n);

analyze public.assets;

-- Representative paginated list.
explain (analyze,buffers)
select id,asset_code,name,model,serial_number
from public.assets
where hospital_id=(select hospital_id from _capacity_test_ids)
order by asset_code
limit 25 offset 0;

-- Representative status + department filter.
explain (analyze,buffers)
select id,asset_code,name
from public.assets
where hospital_id=(select hospital_id from _capacity_test_ids)
  and department_id=(select department_id from _capacity_test_ids)
  and operational_status='in_service'
order by asset_code
limit 25;

-- Representative substring search used by the application.
explain (analyze,buffers)
select id,asset_code,name
from public.assets
where hospital_id=(select hospital_id from _capacity_test_ids)
  and (name ilike '%Capacity Test Asset 099%'
       or asset_code ilike '%CT-%'
       or model ilike '%TEST-MODEL-42%'
       or serial_number ilike '%CAP-SN-9999%')
order by asset_code
limit 25;

-- Confirm exactly 10,000 synthetic rows were generated before rollback.
select count(*) as synthetic_assets_created
from public.assets
where hospital_id=(select hospital_id from _capacity_test_ids);

rollback;
