# Batch 8 — Legacy fault and service history linkage

Migration `202611260007_link_legacy_history.sql` adds a nullable `asset_id` to the existing `faults` and `services` tables.

## What it does

- Adds foreign keys from both history tables to the canonical `assets` table.
- Backfills `asset_id` by matching each history row's existing `device_id` to `devices.id`, then to `assets.legacy_device_id`.
- Adds indexes for asset-based fault and service history retrieval.
- Adds triggers that populate `asset_id` when the existing application inserts a fault or service row using the old `device_id` field.
- Leaves all existing history rows, legacy `device_id` values, and current application insert payloads unchanged.

This is a compatibility bridge: it creates a canonical asset reference alongside the legacy device reference. It does not switch the operational app to writing directly to `assets`, and it does not prove the legacy table schema is compatible until the migration is run on staging.

## Required staging checks

- [ ] Compare total legacy fault/service rows before and after the migration.
- [ ] Confirm all rows whose device exists in the copied asset register receive an `asset_id`.
- [ ] Investigate rows with null `asset_id` as possible orphaned, retired, or unmapped legacy references.
- [ ] Create a test fault through the existing public QR flow and confirm its `asset_id` is populated.
- [ ] Create a test service record through the existing engineer interface and confirm its `asset_id` is populated.
- [ ] Confirm the legacy device detail page still displays the same fault/service history.
- [ ] Confirm no duplicate fault or service records were created.
