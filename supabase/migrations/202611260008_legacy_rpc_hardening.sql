-- Batch 9: close unintended direct RPC access to internal legacy notification functions.
-- Public QR lookup and fault-report RPCs are intentionally retained for existing QR labels.
-- Trigger/cron execution continues to work; only direct Data API invocation is revoked.

begin;

do $$
begin
  if to_regprocedure('public.notify_new_fault()') is not null then
    execute 'revoke execute on function public.notify_new_fault() from public, anon, authenticated';
  end if;

  if to_regprocedure('public.send_daily_digest()') is not null then
    execute 'revoke execute on function public.send_daily_digest() from public, anon, authenticated';
  end if;
end;
$$;

commit;

-- The following public endpoints remain intentionally callable:
--   get_device_public(text): read-only information required by legacy QR labels.
--   report_fault(text,text,text,text,text): validates and submits public QR fault reports.
-- Review their rate limiting and data disclosure periodically.
