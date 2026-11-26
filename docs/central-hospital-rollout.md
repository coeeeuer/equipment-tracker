# Central Hospital rollout notes

## Scope delivered in this branch

- Adds a hospital location directory for wards and departments.
- Seeds the eight initial locations agreed for Central Hospital.
- Adds a generator register separate from medical equipment.
- Adds individual generator profiles, basic refuelling records, service history and breakdown history.
- Adds application roles for `admin`, `biomedical` and `viewer` on the new hospital modules.
- Keeps existing `devices.ward` values as text for backward compatibility. Existing equipment, fault, service and audit tables are not altered by the migration.
- Bumps the service-worker cache version so installed app copies can receive the new interface.

## Important: database migration required

The new screens are deliberately fail-soft: if the migration has not been applied, existing equipment tracking should continue to load, while the new hospital modules display a migration/role notice. The new screens cannot save records until the SQL migration has been applied in the Supabase project.

1. Take a current Supabase database backup.
2. Open Supabase Dashboard → SQL Editor.
3. Review and run `supabase/migrations/202611260001_central_hospital_modules.sql`.
4. In Supabase Authentication → Users, identify the account that Central Hospital has designated as the first application administrator.
5. Copy that user's Auth UUID and run the bootstrap statement at the bottom of the migration, replacing the placeholder UUID.
6. Assign biomedical staff and read-only users by inserting their Auth UUIDs into `public.app_user_roles`, with role `biomedical` or `viewer`.
7. Sign out and back in to refresh the app role, then verify access using one account per role.

Example role assignment (replace the UUID with the real Auth user UUID):

```sql
insert into public.app_user_roles (user_id, role)
values ('REPLACE-WITH-AUTH-USER-UUID', 'biomedical')
on conflict (user_id) do update
set role = excluded.role, updated_at = now();
```

The repository does not contain a Supabase service-role key, and the application must never receive one. Role assignment is therefore an administrator-controlled Supabase operation for this first release; no staff can promote themselves from inside the app.

## Role behaviour for the new modules

| Role | View locations/generators | Register/edit locations and generators | Add fuel/service/breakdown records | Delete generator records |
|---|---|---|---|---|
| admin | Yes | Yes | Yes | Yes, via database policy |
| biomedical | Yes | Yes | Yes | No |
| viewer | Yes | No | No | No |
| no role | No module access | No | No | No |

The existing equipment module has its pre-existing permissions and policies; this migration does not silently change them. Before hospital-wide production use, an administrator should review the existing RLS policies for `devices`, `faults`, `services`, `audits` and the public QR-report RPC. The new role model does not automatically retrofit security onto those existing tables.

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

- [ ] Apply the migration to a backed-up Supabase project.
- [ ] Assign the first admin and at least one biomedical account.
- [ ] Confirm viewer accounts can read but cannot write to the new modules.
- [ ] Confirm unauthorised accounts cannot read or write the new modules.
- [ ] Confirm all eight locations appear exactly once.
- [ ] Register both generators from their physical nameplates; do not copy unverified reference values into the actual records.
- [ ] Test a generator edit, refuelling entry, service entry and breakdown entry.
- [ ] Verify each generator's history remains separate.
- [ ] Verify existing equipment registration, QR fault reporting, audits, imports, exports and offline reporting still work.
- [ ] Verify installed PWA clients refresh to the new service-worker cache.
- [ ] Review existing-table RLS policies before production rollout.

## Current limitations

This branch changes the repository only. It does not apply the Supabase migration, create user accounts, assign staff roles, or deploy the live site. Those are separate controlled rollout steps. Browser-level end-to-end tests against the hospital's actual Supabase project have not been run from this environment.
