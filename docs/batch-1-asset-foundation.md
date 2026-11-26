# Batch 1 — Hospital-wide asset database foundation

## Scope
This is an additive database foundation for Central Hospital. It introduces hospitals, departments, physical locations, categories, a canonical asset register, accessory relationships, transfers, asset documents and an asset audit log.

## Compatibility and data preservation
- The existing `devices`, `faults`, `services` and `audits` tables are not dropped, renamed or rewritten.
- Existing equipment is copied into `public.assets` with its original `devices.id` preserved in `legacy_device_id`.
- Existing `devices.ward` values are mapped to normalised departments. Unknown ward names are retained by creating a department record rather than discarding the text.
- The old equipment table remains the compatibility source until a later application batch has been built and tested.
- Existing generator profiles remain in `public.generators`; the new nullable `asset_id` allows later linking to the central asset register without inventing generator records.

## QR identity requirement
The canonical asset has a stable UUID and a human-readable `asset_code`. The later QR implementation must encode a versioned payload containing:
- asset ID / asset code;
- department ID and department name at the time the label is generated;
- the application route for lookup.
The scanner must treat the database as authoritative and compare the encoded department with the current department. A transfer must refresh/reprint the QR label or display a clear stale-label warning. Do not use a ward name alone as the asset's unique identity.

## Important boundaries
- This migration is not yet approved for production.
- It has not been run against the live Supabase database or a restored staging copy.
- The migration assumes the preceding hospital-modules migration has created `hospital_locations`, `generators`, `app_user_roles`, `devices`, and the `public.has_app_role(text[])` helper.
- Before staging execution, inspect the live schema for exact column types, constraints, RLS policies, grants, and existing row counts.
- Run the SQL in a restored staging project first, then compare source and copied row counts and department mappings.
- Take a verified database backup and storage backup before any production migration.
- No production database, live website, or `main` branch is changed by preparing this file.

## Staging verification
1. Record counts from `devices`, `faults`, `services`, `audits`, `generators` before migration.
2. Apply the migration to a restored staging copy.
3. Confirm `assets` contains one row for each legacy device.
4. Confirm there are no unmapped `legacy_device_id` values.
5. Review any device whose original ward does not match its linked department.
6. Confirm generator rows remain unchanged and `asset_id` is nullable.
7. Test role access with separate admin, biomedical and viewer accounts.
8. Do not proceed to production until the application has been updated to read/write the canonical register safely and rollback has been rehearsed.

## Known limitation for this batch
Department-level staff access is intentionally not enabled yet. The first-stage policies permit authenticated reads and restrict changes to the existing admin/biomedical roles. Department-scoped roles and policies will be introduced with the staff-access batch after the department assignment model is finalised.
