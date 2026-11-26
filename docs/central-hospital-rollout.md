# Central Hospital rollout notes

## Scope delivered in this branch

- Adds a hospital location directory for wards and departments.
- Adds a read-only canonical asset register screen with database-side search, status/department/category filters and server-side pagination (25/50/100 rows).
- Seeds the eight initial locations agreed for Central Hospital.
- Adds a generator register as a specialist module linked to the universal asset register by a canonical asset identity.
- Adds individual generator profiles, basic refuelling records, service history and breakdown history.
- Adds application roles for `admin`, `biomedical` and `viewer` on the new hospital modules.
- Keeps existing `devices.ward` values as text for backward compatibility. Existing equipment, fault, service and audit tables are not altered by the migration.
- Adds department-aware QR payloads while retaining support for legacy `EQ-…` labels.
- Flags QR labels whose encoded department no longer matches the current device record.
- Disables permanent device deletion in the interface; assets should be retired so their history remains available.
- Bumps the service-worker cache version so installed app copies can receive the new interface.

## Important: database migration required

**Do not run these migrations against production yet.** The original schema for the legacy `devices`, `faults`, `services` and `audits` tables has not been independently verified. Apply the sequence below only to a restored staging copy first.

1. Take a current Supabase backup and prove it can be restored to an isolated staging project.
2. Review the actual legacy table definitions, foreign keys, triggers, indexes and RLS policies against the assumptions in `docs/batch-2-compatibility-review.md`.
3. Apply `supabase/migrations/202611260001_central_hospital_modules.sql` to staging.
4. Apply `supabase/migrations/202611260002_hospital_asset_foundation.sql` to staging. Compare legacy device counts with copied asset counts and resolve every unmapped department before proceeding.
5. Apply `supabase/migrations/202611260003_link_generators_to_assets.sql` to staging. Confirm every generator profile links to exactly one canonical asset.
6. Apply `supabase/migrations/202611260004_asset_audit_triggers.sql` to staging. Verify create/update/transfer audit events and transaction rollback behaviour.
7. Apply `supabase/migrations/202611260005_department_membership_rls.sql` to staging. Test role and department access using separate test accounts.
8. Only after the staging checks pass, the hospital's authorised administrator may decide whether to schedule a production migration. Production execution requires a fresh backup and explicit approval.

The repository does not contain a Supabase service-role key, and the application must never receive one. The first administrator must be designated by the hospital and assigned using the Auth UUID from Supabase Authentication → Users. Do not share credentials or use a shared staff account.

Example central Biomedical role assignment (replace the UUID with the real Auth user UUID):

```sql
insert into public.app_user_roles (user_id, role)
values ('REPLACE-WITH-AUTH-USER-UUID', 'biomedical')
on conflict (user_id) do update
set role = excluded.role, updated_at = now();
```

Department memberships should be created only by admin/Biomedical after the user and department have been verified. The department membership migration is a database foundation; the app does not yet provide a staff membership administration screen.

## Role behaviour

### Existing locations and generator module

| Role | View locations/generators | Register/edit locations and generators | Add fuel/service/breakdown records | Delete generator records |
|---|---|---|---|---|
| admin | Yes | Yes | Yes | Yes, via database policy |
| biomedical | Yes | Yes | Yes | No |
| viewer | Yes | No | No | No |
| department_officer | No additional generator permissions | No | No | No |
| maintenance | No additional generator permissions | No | No | No |
| no role | No module access | No | No | No |

### Canonical asset register after migration 005

| Role | Asset visibility | Canonical asset changes |
|---|---|---|
| admin | All hospital assets | Full central oversight |
| biomedical | All hospital assets | Full central oversight |
| viewer | All hospital assets | Read-only |
| department_officer | Active assigned departments only | Create/update only within an active asset-officer membership |
| maintenance | Active assigned departments only | Read-only |
| no role | No access | No access |

The existing equipment module has its pre-existing permissions and policies; these migrations do not silently change them. Migration 005 scopes access to canonical assets, but the legacy equipment permissions remain a separate review item. The current canonical asset register UI is read-only; department-officer create/edit screens and membership administration are not yet implemented. Before hospital-wide production use, an administrator should review the existing RLS policies for `devices`, `faults`, `services`, `audits` and the public QR-report RPC. The new role model does not automatically retrofit security onto those existing tables.

## Initial hospital locations

The migration inserts these eight rows, using `ON CONFLICT DO NOTHING` so rerunning the seed does not duplicate names:

- Maternity Ward (ward)
- Eye Clinic (department)
- Female Ward (ward)
- Amenity Ward (ward)
- Male Ophthalmic Ward (ward)
- Operating Theatre (department)
- X-Ray / Ultrasound Unit (department)
- Accident and Emergency (department)

Locations can be deactivated instead of deleted, preserving the meaning of existing equipment records. The equipment form uses the registered active locations once the migration is available.

## Generator data: verified evidence vs reference specifications

No generator records are automatically inserted. This is intentional: the hospital's actual generator serial numbers, installed configurations, hour-meter readings, fuel-tank capacities and current condition must be captured from the actual machines and their documents.

### Large generator photographed by the user

The photographed nameplate identifies an FG Wilson P150-5. The legible nameplate values are:

| Field | Nameplate value |
|---|---:|
| Manufacturer | Caterpillar (NI) Limited / FG Wilson |
| Model | P150-5 |
| Manufacture month/year | 05/2025 |
| Standby rating | 150 kVA / 120 kW |
| Prime rating | 135 kVA / 108 kW |
| Voltage | 400/230 V |
| Phases | 3 |
| Power factor | 0.8 |
| Frequency | 50 Hz |
| Standby current | 217 A |
| Prime current | 195 A |
| Rated speed | 1,500 rpm |
| Nameplate ambient reference | 25°C |

The manufacturer product page confirms the 50 Hz P150-5 rating as 135 kVA / 108 kW prime and 150 kVA / 120 kW standby. The published technical sheet lists Perkins 1106A-70TG1 as the standard engine configuration, but the actual hospital engine plate should be checked before entering that as confirmed for this exact set.

References:
- https://www.fgwilson.com/en_GB/products/new/fg-wilson/diesel-generators/small-range-220-kva/1000004202.html
- https://www.fgwilson.com.tr/assets/images/fgw2024-03-08T14-54-38.048Z.pdf

### Smaller generator photographed by the user

The second photograph shows the marking `P88-3`. This is a useful model clue, but it is not a readable manufacturer identification plate. FG Wilson's published P88-3 50 Hz ratings are 80 kVA / 64 kW prime and 88 kVA / 70.4 kW standby. Published configurations commonly list a Perkins 1104A-44TG2 engine, but the actual small generator's nameplate and engine plate must be photographed before those values are saved as the hospital unit's confirmed specifications.

References:
- https://www.fgwilson.com/en_GB/products/new/fg-wilson/diesel-generators/small-range-220-kva/1000004203.html
- https://static1.squarespace.com/static/54b6de2ee4b013117df53e27/t/54ca8beee4b07ef07a3f3adc/1422560238913/P88-3%284PP%29GB%280714%29.pdf

### Fuel and servicing safeguards

- Fuel records capture refuelling date/time, litres, amount paid, optional hour-meter reading, supplier/source and notes.
- The app does not calculate fuel consumption from a refuelling event. A defensible consumption calculation needs a measured operating-hour interval and comparable fuel-level or fuel-used data.
- Service logs accept date- and hour-based next-due information, but the app does not invent service intervals.
- Enter maintenance intervals, oil grades, coolant types, capacities and inspection criteria only after checking the correct operation/maintenance manual for the exact generator/engine configuration or obtaining written guidance from the authorised service provider.
- Load-test readings and detailed electrical performance tests are not yet represented as a structured test form in this first implementation. They should be added only after the hospital confirms its testing procedure and required measurements.

## Validation checklist before enabling hospital-wide use

- [ ] Apply migrations 001–004 to a restored staging copy first; do not apply directly to production.
- [ ] Verify the paginated canonical register returns accurate counts and page boundaries with a synthetic 10,000-row dataset.
- [ ] Assign the first admin and at least one biomedical account.
- [ ] Confirm viewer accounts can read but cannot write to the new modules.
- [ ] Verify migration 005 department-scoped read/write policies with separate admin, Biomedical, viewer, department-officer and maintenance test accounts.
- [ ] Confirm unauthorised accounts cannot read or write the new modules.
- [ ] Confirm all eight locations appear exactly once.
- [ ] Register both generators from their physical nameplates; do not copy unverified reference values into the actual records.
- [ ] Test a generator edit, refuelling entry, service entry and breakdown entry.
- [ ] Verify each generator's history remains separate.
- [ ] Verify the asset audit triggers record create/update/transfer events and do not permit unauthorised audit-row mutation.
- [ ] Verify existing equipment registration, QR fault reporting, audits, imports, exports and offline reporting still work.
- [ ] Verify new QR labels contain the department name and, when configured, department directory ID.
- [ ] Transfer a test device and confirm its old QR label displays a stale-location warning; print and test the replacement label.
- [ ] Verify old QR labels still open the existing public fault-report route.
- [ ] Verify installed PWA clients refresh to the new service-worker cache.
- [ ] Review existing-table RLS policies before production rollout.

## Current limitations

This branch changes the repository only. It does not apply the Supabase migration, create user accounts, assign staff roles, or deploy the live site. Those are separate controlled rollout steps. Browser-level end-to-end tests against the hospital's actual Supabase project have not been run from this environment.
