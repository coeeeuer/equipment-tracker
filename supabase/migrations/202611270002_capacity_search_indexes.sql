-- Capacity and search tuning for the canonical hospital asset register.
-- Prerequisites: migrations 001-009 and asset work-order migration 010.
-- Additive indexes only; no records or existing constraints are changed.

create extension if not exists pg_trgm with schema extensions;

-- The UI performs case-insensitive substring searches (ILIKE '%term%').
-- Trigram indexes support those exact predicates; the existing tsvector index
-- is retained for future token-based search.
create index if not exists assets_name_trgm_idx
  on public.assets using gin (name extensions.gin_trgm_ops);
create index if not exists assets_code_trgm_idx
  on public.assets using gin (asset_code extensions.gin_trgm_ops);
create index if not exists assets_model_trgm_idx
  on public.assets using gin (model extensions.gin_trgm_ops)
  where model is not null;
create index if not exists assets_serial_trgm_idx
  on public.assets using gin (serial_number extensions.gin_trgm_ops)
  where serial_number is not null;

-- Match common filtered list orders and directory lookups.
create index if not exists assets_hospital_status_code_idx
  on public.assets(hospital_id, operational_status, asset_code);
create index if not exists assets_hospital_department_code_idx
  on public.assets(hospital_id, department_id, asset_code);
create index if not exists assets_hospital_category_code_idx
  on public.assets(hospital_id, category_id, asset_code);

create index if not exists departments_hospital_active_name_idx
  on public.departments(hospital_id, active, name);
create index if not exists locations_hospital_department_active_name_idx
  on public.locations(hospital_id, department_id, active, name);
create index if not exists asset_categories_hospital_active_name_idx
  on public.asset_categories(hospital_id, active, name);

create index if not exists asset_work_orders_hospital_due_date_idx
  on public.asset_work_orders(hospital_id, next_due_date, asset_id)
  where status <> 'cancelled' and next_due_date is not null;
create index if not exists asset_audit_logs_hospital_created_idx
  on public.asset_audit_logs(hospital_id, created_at desc);
