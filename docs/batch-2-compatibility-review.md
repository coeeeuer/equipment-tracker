# Batch 2 — Asset register compatibility review

## Status

**Review complete; implementation is deliberately gated.** This batch has not switched the application to `public.assets`, changed existing equipment writes, or altered QR payloads. Those changes would be unsafe until the live Supabase schema and legacy-record mapping are verified.

## Existing application behaviour confirmed from the current development branch

- The current operational register reads from `public.devices`.
- Device create and edit forms write to `public.devices`; retire and delete actions also target that table.
- Faults and service history are associated through `device_id` and are rendered against the legacy device ID.
- The app loads all devices in one request. Fault and service history are each capped at 5,000 rows. This is not yet a suitable scaling strategy for the agreed 1,000–3,000 initial assets and future growth to at least 10,000.
- Search and status filters currently run in browser memory, not in the database.
- QR codes currently contain a public fault-report URL ending in the legacy device ID. The ward is printed as visible text but is **not encoded in the QR payload**.
- The public report route parses a legacy `EQ-…` identifier. Replacing that payload before a backward-compatible resolver exists would invalidate existing printed labels.
- The current equipment form uses a free-text legacy ward value if the new location directory is unavailable.

## New canonical model confirmed in Batch 1

The additive migration creates `hospitals`, `departments`, `locations`, `asset_categories`, `assets`, `asset_relationships`, `asset_transfers`, `asset_documents` and `asset_audit_logs`.

Existing devices are copied into `assets` with:
- `assets.legacy_device_id = devices.id::text`
- the old name, model, serial, ward mapping, critical flag, replacement cost, warranty and vendor details copied where available
- original `devices`, `faults`, `services` and `audits` rows left untouched

This is a compatibility bridge, not yet a complete application migration. In particular, the current UI still reads and writes the legacy tables.

## Why the application migration is gated

The repository does not contain the original database-creation migration for `devices`, `faults`, `services` and `audits`. The live production schema was therefore inspected directly on 2026-11-28. The expected `devices` columns exist with compatible types: `id` is text with the `EQ-` sequence default; `name` and `ward` are non-null text; `model` and `serial` are nullable text; `critical` is boolean; warranty and added dates are date; replacement cost is numeric; and vendor fields are text. `faults.device_id` and `services.device_id` are text foreign keys to `devices.id` with `ON DELETE CASCADE`. Their primary keys and device-history indexes exist. The existing `faults_notify` trigger and public QR lookup/report functions were also identified.

The live policies on the four legacy tables currently grant full access to authenticated users. The HOD-approved single Biomedical Engineering login means no ward accounts will be created; wards use only the public QR lookup and reporting RPCs. This does not remove the need to verify that these public routes disclose only the intended information.

At the 2026-11-28 inspection, all four live legacy tables contained zero rows. Consequently the backfill's column and type assumptions have been checked, but populated-data mapping and non-empty legacy history migration remain untested and require a restored staging copy. No production migration was applied.

## Batch 2 implementation design

1. Keep the existing device/fault/service workflow operational while introducing a canonical asset data-access layer.
2. Use `assets.id` as the immutable internal identity and `asset_code` as the human-readable hospital asset number. Preserve `legacy_device_id` for existing QR labels and historical links.
3. Define explicit compatibility mapping between canonical assets and legacy devices. Do not dual-write to both tables until a database transaction/RPC or equivalent reliable synchronisation mechanism is in place.
4. Add the hospital-wide register with server-side pagination (25 by default; 50/100 selectable), database-side search and filtering, and a separate asset detail route.
5. Keep existing fault and service history visible for legacy-linked assets. New asset fault/service workflows must use a deliberate shared identity strategy; do not silently create orphaned histories.
6. Treat each individually tracked accessory as its own asset, optionally linked to a parent asset. Bulk disposable stock belongs in a later inventory module.
7. Make department and physical room separate fields. Department transfers must be recorded, not merely overwrite a text label.
8. Introduce versioned QR payloads only after the scanner can resolve both legacy and canonical identifiers. Include the canonical asset ID/code and department ID/name in the new QR payload; compare the encoded department against the current database record and flag stale labels after transfers.
9. Add role enforcement, audit logging, and tested RLS policies before enabling writes for department staff.

## Required staging evidence before switching writes

- A schema-only export or SQL definitions for the existing `devices`, `faults`, `services` and `audits` tables, including indexes, foreign keys, triggers, RPCs and RLS policies.
- A current staging backup and confirmation that it can be restored.
- Counts of legacy devices and copied assets, plus a zero-unmapped-row check.
- A sample comparison of legacy ward values to canonical department assignments.
- Tests proving existing fault reports, service logs, audit, import/export and printed QR labels still work.
- A tested rollback procedure.

## Work completed after this review

A read-only canonical asset register screen has now been added at `#/assets`. It queries `public.assets` directly and uses database-side search, status/department/category filters, exact row counts and server-side pagination (25, 50 or 100 rows per page). It is intentionally separate from the legacy equipment register and does not create, edit, transfer or delete records. If the Batch 1 schema is not installed, it displays a clear unavailable message without blocking the existing equipment module.

The complete legacy-to-canonical write compatibility layer remains gated on verified database schema and staging tests. The existing equipment register still reads and writes `devices`, and its legacy data loading remains unpaginated. Do not claim the entire application has been load-tested for 10,000 assets.

## Next implementation step

Obtain the schema evidence, verify the foundation migration on a restored staging copy, and then complete canonical asset create/edit/transfer workflows and a tested compatibility strategy for existing fault/service history. Do not apply migrations to production or merge/deploy this branch without explicit approval.
