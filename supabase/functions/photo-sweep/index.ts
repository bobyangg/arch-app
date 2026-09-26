// Removing photo files that no photograph owns any more.
//
// Deleting a photograph, or an account, removes the `photos` row and leaves the
// file, because Supabase refuses deletes on `storage.objects` from SQL. Only the
// Storage API may remove a file, so this is where it happens: `private.sweep_photos`
// calls it hourly when there is anything to remove, with the same cron secret the
// push sweep uses.
//
// "Orphaned" is decided in SQL by `public.orphaned_photo_paths` -- a file in the
// photo bucket with no `photos` row, more than an hour old -- and not here, so the
// rule lives in one place and can be tested against the database directly.

import { admin, json, refuse } from "../_shared/http.ts";

const BATCH = 500;

Deno.serve(async (request) => {
  const expected = Deno.env.get("PUSH_CRON_SECRET");
  if (!expected || request.headers.get("x-arch-cron") !== expected) {
    return refuse(401, "not for you");
  }

  const db = admin();
  const { data, error } = await db.rpc("orphaned_photo_paths", { max_rows: BATCH });
  if (error) return refuse(500, "could not list orphaned photos", error);

  const paths = ((data ?? []) as Array<{ path: string }>).map((row) => row.path).filter(Boolean);
  if (!paths.length) return json({ status: "ok", removed: 0 });

  const { data: removed, error: removeError } = await db.storage.from("photos").remove(paths);
  if (removeError) return refuse(500, "could not remove orphaned photos", removeError);

  // A count, never the paths: they are account ids and photo ids, and a log is
  // read by more people than the database is.
  console.log("removed orphaned photos", removed?.length ?? 0);
  return json({ status: "ok", removed: removed?.length ?? 0 });
});
