-- Arch: when the matcher runs.
--
-- Hourly, not once at 13:00 UTC.
--
-- pg_cron runs on UTC, and 9am New York is 14:00 UTC in January but 13:00 in
-- July -- verified against this database. A fixed expression is therefore an hour
-- early for seven months of the year. `run_nightly_match` checks the New York hour
-- itself and takes the first tick at or after nine.
--
-- The guard earns its keep twice over: a tick the scheduler misses is picked up by
-- the next one, so a roster arrives late rather than not at all. A fixed
-- expression has no second chance, and Supabase's own pg_cron notes are explicit
-- that the scheduler worker can die without the job firing.
--
-- Minute 7 rather than 0: off the busiest minute of the hour, and easy to pick out
-- of cron.job_run_details.

create extension if not exists pg_cron;

select cron.schedule(
    'arch-nightly-match',
    '7 * * * *',
    $$select private.run_nightly_match()$$
);

-- Health, when it matters:
--
--   select * from match_runs order by night desc limit 7;
--   select * from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'arch-nightly-match')
--    order by start_time desc limit 24;
--
-- `match_runs.held` and `.empty` are the same starvation numbers
-- `matcher/analysis.py` reports, so production can be read against the simulation
-- rather than only against itself.
