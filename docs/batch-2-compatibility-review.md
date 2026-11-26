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

The repository branch does not contain the original database-creation migration for `devices`, `faults`, `services` and `audits`. The current JavaScript shows which columns it expects, but does not prove their database types, nullability, defaults, foreign keys, delete behaviour, RLS policies or any triggers/RPC dependencies.

The Batch 1 backfill currently assumes these `devices` columns exist with compatible types: `id`, `name`, `model`, `serial`, `ward`, `critical`, `replacement_cost`, `warranty_until`, `vendor` and `vendor_phone`. It also assumes that `id::text` is an acceptable unique legacy identifier. These assumptions must be checked against the actual Supabase schema before migration execution.

No Supabase database connector or staging database connection is available in this repository session. Therefore the live schema, row counts, RLS policies and migration execution cannot be verified here. No live database or deployed app has been touched.

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

## Next implementation step

Once the schema evidence is available, complete the compatibility layer and server-paginated register on this development branch. Do not apply Batch 1 migrations to production or merge/deploy this branch as part of this review.
