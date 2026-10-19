-- The push sweep asks about what `push` will actually send.
--
-- `sweep_push` counted every unsent row, and `push` takes only the ones with
-- fewer than five attempts. Sixteen rows from the week the APNs key was
-- sandbox-only had used all five, so the count was never zero and the sweep made
-- a request every minute for a function that then found nothing to do. They are
-- left where they are -- given up, and worth a look, as 012 says -- and are no
-- longer counted.

create or replace function private.sweep_push()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
    url text;
    secret text;
    waiting integer;
begin
    -- Nothing queued is the common case by a long way. Skipping the request keeps
    -- a minute-by-minute job from being a minute-by-minute HTTP call. `attempts`
    -- matches the function's own MAX_ATTEMPTS.
    select count(*) into waiting from push_outbox where sent_at is null and attempts < 5;
    if waiting = 0 then return; end if;

    select value into url from private_settings where key = 'push_url';
    select value into secret from private_settings where key = 'push_secret';
    if url is null or secret is null then return; end if;

    perform net.http_post(
        url := url,
        body := '{}'::jsonb,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-arch-cron', secret
        ),
        timeout_milliseconds := 30000
    );
end;
$function$;
