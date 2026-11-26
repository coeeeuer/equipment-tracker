# Batch 3 — Generator linkage and QR continuity

## Generator linkage

Migration `202611260003_link_generators_to_assets.sql` creates one canonical asset record for every existing generator profile, using an asset code prefixed with `GEN-`. It then links the specialist `generators.asset_id` to the canonical `assets.id`.

The specialist generator module remains responsible for generator-specific technical specifications, refuelling, maintenance and breakdown history. The universal asset record provides the shared hospital identity, category, criticality and high-level status.

The migration is additive and idempotent:
- It does not delete generator profiles or history.
- It preserves existing non-null generator-to-asset links.
- It does not create invented generator specifications.
- Unknown generator status remains `unknown` in the canonical asset record.
- It attempts to map a generator's location text to a department only when the names match exactly after trimming and case normalisation. Unmatched locations remain unassigned for review.

## QR implementation in the existing equipment workflow

New equipment QR labels use a versioned URL payload with:
- legacy equipment ID (to keep existing fault-report and service-history links working);
- QR payload version;
- department name;
- department directory ID when the directory mapping is available.

The scanner accepts both old QR labels and the new URL payload. When the department encoded on a new label differs from the current device ward in the database, the authenticated device view and public fault-report view display a stale-label warning. The warning asks staff to confirm the asset and reprint the label after a transfer.

The current QR implementation remains a compatibility bridge: it encodes the department name and optionally its directory ID, but the current equipment table still stores ward as free text. The full canonical asset QR identity and transactional transfer workflow depend on the verified database migration and later application integration.

## Data preservation

Permanent deletion has been removed from the equipment detail interface. The UI directs staff to retire equipment instead, preserving its history. The old delete event handler now refuses a permanent deletion if invoked, but the underlying database policies and any direct database access must still be reviewed before production use.

## Verification status

- Repository files committed to the development branch.
- Static source inspection confirms the QR payload contains the department name and optional directory ID.
- Static source inspection confirms the scanner still extracts legacy `EQ-…` identifiers.
- Static source inspection confirms the public report route receives QR metadata and compares the encoded department with the current record.
- Static source inspection confirms the equipment detail UI no longer offers permanent deletion.
- Not yet verified: browser execution, physical camera scanning, actual printed QR readability, Supabase schema compatibility, staging migration execution, role/RLS behaviour or production PWA refresh.
