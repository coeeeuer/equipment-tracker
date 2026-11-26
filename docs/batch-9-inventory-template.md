# Batch 9 — Initial asset inventory preparation

Template: `templates/central-hospital-asset-import-template.csv`

This is a blank collection template for the hospital's initial asset census. It is not yet an in-app bulk importer. The columns align with the canonical asset foundation and allow individually tracked accessories to be linked to parent equipment after the assets have been assigned their official codes.

## Data-entry rules

1. Use one row for each individually tracked asset. Include small devices and accessories where the hospital needs to identify, locate, maintain or audit them individually.
2. Do not add disposable consumables (for example, single-use electrodes, syringes or gloves) to the fixed-asset register. Those belong in a future stock/inventory module.
3. Leave `asset_code` blank for new records; the database code-generation trigger assigns a unique code after migration 006 is applied. Do not invent codes manually.
4. Use a department/ward name from the approved directory. If the department is missing, record it separately for Biomedical Engineering to approve and add before import.
5. Use `location_name` for the physical room/store/theatre room, not as a substitute for the department.
6. Record manufacturer, model and serial number exactly as shown on the equipment label. If a value is unreadable, leave it blank and flag the record for verification.
7. Do not guess acquisition date, cost, warranty or condition. Use blank where the source document is unavailable.
8. Mark `critical=true` only when the hospital confirms that failure could directly interrupt life-support, emergency response or another critical clinical service.
9. For accessories, create a separate row only when individual traceability is required. After official asset codes exist, use `parent_asset_code` and `relationship_type=accessory` to link the child accessory to its parent.
10. Do not enter patient names, patient IDs, diagnoses, images containing patient details or any other patient-identifying information.

## Allowed values

- `asset_kind`: equipment, accessory, furniture, ict, infrastructure, other.
- `operational_status`: unknown, in_service, under_maintenance, out_of_service, in_storage, retired, missing.
- `physical_condition`: excellent, good, fair, poor, unserviceable, unknown.
- `critical`: true or false.
- `relationship_type`: accessory, component, peripheral, paired_with.

Category codes are seeded in the database: MEDICAL, IMAGING, LAB, ICT, FURNITURE, ELECTRICAL, POWER, FACILITY and OTHER.

## Import status

Bulk import into `assets` is not enabled in the UI yet. First verify the migrations and legacy schema on staging, then build and test a transactional importer with duplicate checks, department/location validation, row-level error reporting and a rollback-safe preview. Continue using the existing equipment import only for the legacy register until that canonical importer is ready.
