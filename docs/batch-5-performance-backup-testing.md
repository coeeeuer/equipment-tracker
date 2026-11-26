# Batch 5 — Performance, backup and validation plan

## Implemented in the application

The canonical asset register screen fetches only the requested page from Supabase:
- default page size: 25;
- selectable page sizes: 50 and 100;
- database-side search across name, asset code, model and serial number;
- database-side status, department and category filters;
- exact result count and page navigation.

The page is read-only. It does not change the existing equipment register's data path.

## Known performance limitation

The legacy operational equipment module still loads all `devices` rows in one request and loads up to 5,000 faults and 5,000 service records into browser memory. The new canonical page does not fix that older path. The existing dashboard calculations also use in-memory records.

Therefore the application has **not** yet been verified for 10,000 live assets or 50 concurrent users. A full scale-readiness claim would be premature until the legacy module is migrated or independently paginated and database query plans have been measured.

## Recommended staging performance test

Use synthetic, non-patient data only.

1. Restore a current database backup to an isolated staging project.
2. Apply reviewed migrations 001–004 in order.
3. Load 10,000 synthetic assets distributed across the nine initial categories and the active departments; include accessories and assets with unknown or missing status.
4. Add realistic synthetic faults, service history and transfer events.
5. Verify that a 25-row page returns at most 25 asset rows and that next/previous navigation does not skip or duplicate rows.
6. Test search terms against asset name, asset code, model and serial number.
7. Test every filter alone and in combination.
8. Inspect query plans for the search and common filters; add or adjust indexes only from measured evidence.
9. Simulate 50 concurrent authenticated sessions performing read/search/page operations.
10. Record p50/p95 latency, error rate, database CPU, connection saturation and memory use.

## Backup and recovery requirements

- Take a full database backup before every migration.
- Confirm the backup can be restored to a separate staging project; a successful backup job alone is not proof of recoverability.
- Back up Supabase Storage objects separately, including fault photos and asset documents.
- Keep migration files version-controlled and apply them in order.
- Keep production and staging credentials separate; never place a service-role key in browser code or commit it to Git.
- Define a hospital-approved retention schedule for database backups, photos, manuals, warranty documents and audit history.
- Document who can authorise restore, who performs it, and how staff are notified.
- Test restore of both database rows and linked storage files.

## Operational acceptance checklist

- [ ] Database backup completed and restored successfully to isolated staging.
- [ ] Asset register tested with 10,000 synthetic rows.
- [ ] 50 concurrent read/search sessions tested.
- [ ] Existing legacy equipment workflows regression-tested.
- [ ] QR labels tested with a physical printer and phone cameras.
- [ ] Offline fault-report queue tested through loss and restoration of connectivity.
- [ ] Storage documents/photos backed up and restored.
- [ ] Audit trail and role restrictions tested.
- [ ] Hospital management and Biomedical Engineering approve the operating procedure.

## Current status

The repository now includes a CI workflow that checks the inline JavaScript syntax and flags potentially destructive table operations in migration SQL. A workflow definition has been committed, but no successful GitHub Actions run has yet been confirmed. No database load test, concurrent-user test, backup restore test or end-to-end browser test has been run in this environment.
