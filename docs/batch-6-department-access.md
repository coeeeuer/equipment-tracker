# Batch 6 — Department-scoped access

Migration `202611260005_department_membership_rls.sql` adds a department membership table and canonical-asset row-level security policies.

## Application roles

- `admin`: system administrator; all hospital asset records.
- `biomedical`: central Biomedical Engineering oversight; all hospital asset records.
- `viewer`: management/read-only access across the hospital.
- `department_officer`: can create/update canonical assets only in departments where the user has an active `asset_officer` membership.
- `maintenance`: can read canonical assets only in departments where the user has an active membership; cannot edit the canonical asset record.

Memberships are individual user-to-department assignments. The membership table is managed only by admin or Biomedical Engineering. A user cannot assign themselves to a department.

## Important distinction

The new policies apply to the canonical `assets` and `asset_documents` tables. They do not retrofit the legacy `devices`, `faults`, `services`, `audits` or public QR-report RPC. Those existing permissions must be audited separately before department accounts are used in production.

The current application interface does not yet provide a membership administration screen or department-officer asset editing. The canonical register is read-only in the UI at this stage. The migration is a database enforcement foundation, not a claim that the complete department workflow is ready.

## Example: assign an existing user to a department

Only a designated admin/Biomedical operator should run this after confirming the correct Auth user UUID and department UUID:

```sql
insert into public.app_user_roles (user_id, role)
values ('AUTH-USER-UUID', 'department_officer')
on conflict (user_id) do update set role = excluded.role, updated_at = now();

insert into public.department_memberships
  (hospital_id, department_id, user_id, membership_role, created_by)
values
  ('HOSPITAL-UUID', 'DEPARTMENT-UUID', 'AUTH-USER-UUID', 'asset_officer', auth.uid())
on conflict (hospital_id, department_id, user_id)
do update set membership_role = excluded.membership_role, active = true;
```

For maintenance staff, set the application role to `maintenance` and membership role to `maintenance`. Do not use the global `viewer` role for a department-restricted viewer because global viewers can read all canonical assets.

## Staging permission tests

- [ ] No-role account cannot read canonical assets.
- [ ] Management viewer can read all canonical assets but cannot write.
- [ ] Department officer sees only assets in assigned departments.
- [ ] Department officer can create/update only within an active `asset_officer` membership.
- [ ] Department officer cannot delete assets or mutate audit logs.
- [ ] Maintenance account sees only assigned-department assets and cannot edit them.
- [ ] Removing/deactivating a membership immediately removes department access.
- [ ] Admin/Biomedical retain central oversight.
- [ ] Legacy equipment permissions are tested independently.
