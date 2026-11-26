# Batch 7 — Canonical asset identity and numbering

Migration `202611260006_asset_code_generation.sql` adds a concurrency-safe asset-code counter per hospital.

## Code format

For Central Hospital, newly created canonical assets receive codes in the format:

`CH-000001`, `CH-000002`, and so on.

The prefix is derived from the initials of the first two hyphen-separated parts of the hospital slug; `central-hospital` therefore produces `CH`. The counter is updated transactionally, so simultaneous inserts do not rely on a browser-generated number.

## Compatibility rules

- Existing legacy device asset codes (the copied `EQ-…` identifiers) are preserved.
- Existing generator asset codes (`GEN-…`) are preserved.
- A caller may supply an explicit asset code; the trigger only generates a code when the value is blank or null.
- The generated code is unique within a hospital through the existing `assets(hospital_id, asset_code)` constraint.
- The counter table is not directly readable or writable by ordinary authenticated/anonymous clients; the trigger function performs the allocation.

## QR implications

The new code is intended as the stable printed hospital asset identifier for canonical assets. The current QR bridge still encodes the legacy device ID for existing equipment because fault reports and service history still depend on it. A later QR cutover must support both canonical asset IDs and legacy IDs before labels are replaced.

## Staging checks

- [ ] Insert new assets without specifying `asset_code`; confirm codes are generated.
- [ ] Run concurrent inserts; confirm uniqueness and monotonic counter progression.
- [ ] Confirm old `EQ-…` and `GEN-…` codes remain unchanged.
- [ ] Confirm a supplied approved code is preserved.
- [ ] Confirm a duplicate supplied code is rejected by the unique constraint.
