# Batch 4 — Audit trail and governance controls

## Canonical asset audit events

Migration `202611260004_asset_audit_triggers.sql` adds database-side audit capture for canonical assets and transfer records.

- Asset creation stores the complete post-insert asset row.
- Asset updates store before/after JSON snapshots.
- Asset deletion stores a deletion event with the deleted row in `before_data`; the audit row does not reference a row that no longer exists.
- Transfer insertion records source and destination department/location, transfer date, reason and approver.
- The audit actor is taken from the authenticated Supabase session (`auth.uid()`), not a browser-supplied name.
- Asset `updated_at` is set by a database trigger.
- Audit triggers run in the same database transaction as the underlying change. If audit insertion fails, the corresponding asset change should fail too.

The migration does not change the old `audits` table or retrofit auditing onto legacy `devices`, `faults` and `services`. That work requires schema and RLS verification.

## Governance baseline

- Biomedical Engineering remains the central administrative authority for the asset register.
- Department staff should have individual accounts, never shared logins.
- Department asset officers should only manage assets assigned to their department.
- Maintenance staff should be able to view assigned equipment and record authorised maintenance actions, without broad permission to change ownership, department, asset identity or delete records.
- Management viewers should be read-only.
- Transfers should record source, destination, reason, date, recorder and approval. A transfer must not silently overwrite the audit trail.
- Retired assets should remain searchable with their complete history.
- Patient-identifying information must not be stored in asset notes, QR payloads, fault descriptions or attached asset documents.

## Security limitations still requiring implementation/verification

The first foundation migration currently grants authenticated users read access to canonical asset records and reserves writes to the central `admin` and `biomedical` roles. Department-specific membership and least-privilege row policies are not yet active. The existing legacy equipment module has separate, pre-existing policies that must be reviewed independently.

Do not enable department staff accounts until the role and membership model has been implemented, reviewed and tested on staging. Do not treat the current UI's role checks as a security boundary; Supabase RLS is the enforcement layer.

## Staging tests

- [ ] Create an asset and confirm exactly one `created` audit event.
- [ ] Update an asset and confirm before/after snapshots are correct.
- [ ] Record a transfer and confirm the source/destination are captured.
- [ ] Confirm an ordinary viewer cannot insert, update or delete audit rows.
- [ ] Confirm an audit-trigger failure rolls back the originating change.
- [ ] Confirm no patient data is present in any test asset or document.
