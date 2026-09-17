-- Twenty-five miles, because the app is no longer one city.
--
-- Ten was right when every place you could choose was inside New York, where ten
-- miles reaches most of four boroughs. The picker now covers the United States
-- and Canada, and ten miles outside a metro is a radius that finds nobody: an
-- empty roster is the one failure this product cannot survive, and a default that
-- produces one for everybody outside a dense city is a default that produces it
-- for most of the map.
--
-- The ceiling does not move. 100 still means "Anywhere" and switches the filter
-- off entirely rather than drawing a 100-mile circle.
--
-- **No rows are updated, and that is not caution about a big table -- there are
-- none.** Nobody has finished onboarding yet. If this runs again when people
-- exist, it must stay a default-only change: a saved radius is somebody's answer
-- and not ours to overwrite.

alter table discovery_settings
    alter column distance_miles set default 25;

comment on column discovery_settings.distance_miles is
    'Miles. 100 means "Anywhere" and switches the distance filter off entirely. '
    'Defaults to 25 -- ten was a New-York-only default and starves anybody '
    'outside a metro now that the picker covers the US and Canada.';
