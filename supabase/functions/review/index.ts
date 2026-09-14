// Arch: notes on your own profile.
//
// The half of the profile review that needs a model. The app sends the words --
// the answers as the reader wrote them, the interests, the few details -- and this
// function fetches the photographs itself from the private bucket, so the bytes
// the reviewer looks at are the bytes the profile shows and nothing the client
// chose to send instead. Then Claude reads all of it and answers in one fixed
// shape: a note per photograph, a note per answer, one paragraph overall.
//
// **What it is told not to do matters more than what it is told to do.** The rest
// of the app refuses to score anybody, and a review that rated your face would be
// the app growing the opinion it has spent every other screen declining to have.
// So the notes are about the photograph as a photograph -- light, distance,
// whether it is clearly you -- and about the writing as writing. Never about the
// person. The system prompt says so, and the schema gives it nowhere to put a
// number.
//
// **A review is read more than it is run.** The answer is stored against a digest
// of what was reviewed, and the same profile gets the same notes back without a
// second call. Fresh reviews are capped per day, because every one costs money
// and a person re-tapping "Ask again" to see whether the model changes its mind
// is not a person the app should indulge.
//
// **Premium, and enforced the way attestation is.** The subscription check reads
// `subscriptions`, which nothing writes yet -- there is no purchase flow. So
// `PREMIUM_ENFORCED` is off until it is set, and a line is logged saying the check
// was skipped, for the same reason `ATTEST_ENFORCED` works that way: a gate
// turned on and enforced in the same change makes the first refusal look like
// every subscriber being locked out.

import Anthropic from "npm:@anthropic-ai/sdk@0.125.0";
import { admin, caller, json, refuse } from "../_shared/http.ts";

const MODEL = "claude-opus-5";

/** Fresh reviews a person can ask for in a day. Stored ones are free. */
const REVIEWS_PER_DAY = 5;

/** The same limits the profile has, so a padded request is refused as a shape. */
const MAX_PROMPTS = 3;
const MAX_INTERESTS = 3;
const ANSWER_LIMIT = 280;
const PHOTO_LIMIT = 6;

const isEnforced = (): boolean =>
  Deno.env.get("PREMIUM_ENFORCED")?.toLowerCase() === "true";

interface Prompt {
  question: string;
  answer: string;
}

interface ReviewRequest {
  name?: string;
  age?: number;
  work?: string;
  prompts: Prompt[];
  interests: string[];
  /** Ask for a fresh review even if one is stored for this exact profile. */
  fresh?: boolean;
}

/**
 * The shape the phone decodes. Kept flat on purpose: one list, each entry naming
 * what it is about, so the screen can lay them beside the things they describe.
 */
const NOTES_SCHEMA = {
  type: "object",
  properties: {
    overall: {
      type: "string",
      description:
        "Two or three sentences on the profile as a whole: what it does well and the one change that would matter most.",
    },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          kind: { type: "string", enum: ["photo", "answer"] },
          position: {
            type: "integer",
            description: "1-based. Photo 1 is the one people see first.",
          },
          verdict: {
            type: "string",
            enum: ["keep", "consider", "change"],
            description:
              "keep: working as it is. consider: fine, and here is a thought. change: this one is costing you something.",
          },
          note: {
            type: "string",
            description:
              "One to three sentences. Specific to this photograph or this answer. For an answer, say what to say instead, not only what is wrong.",
          },
        },
        required: ["kind", "position", "verdict", "note"],
        additionalProperties: false,
      },
    },
  },
  required: ["overall", "items"],
  additionalProperties: false,
} as const;

// Frozen, and first, so that the whole preamble caches across every review the
// project runs. Nothing that varies by person goes in here.
const SYSTEM = `You are reviewing somebody's own dating profile on Arch, at their request, so they can make it better. Arch is a slow, deliberate app: five people a day, no likes, no scores, and long written answers instead of one-liners. Write the way a thoughtful friend with a good eye would, in plain sentences, second person, no headings, no lists inside a note, no exclamation marks.

What you are reviewing:
- Photographs, numbered. Photo 1 is the one people see first, in the roster, before they open the profile.
- Written answers to prompts the person chose. Each is a question and their answer.
- Three interests, and a few details.

What to say about a photograph: only things about the photograph as a photograph. Whether the face is clearly visible and at a readable distance. Light, and whether it flatters or fights. Whether it is a screenshot, a group shot where they are hard to find, a mirror, a car, sunglasses, a filter, a photo of something other than them. Whether the set has variety, or six versions of the same frame. Whether photo 1 is the right one to lead with. Say what to do instead when there is something to do.

What to say about an answer: whether it is specific or generic, whether it gives a stranger something to reply to, whether it says one thing or three, whether the second sentence earns its place. When an answer is vague, say what a specific version would look like, in their voice, without writing it for them. A good answer can simply be told it is good and why.

Never, in any note:
- Comment on the person's attractiveness, body, weight, age, clothes as taste, or how they compare to anyone.
- Guess at their character, income, intentions, or what kind of person they are.
- Score, rank, grade, or estimate how they will do.
- Suggest lying, exaggerating, or performing a personality they do not have.
- Mention that you are an AI, or apologise.

Be kind by being useful. The person asked for this, and "it's great" with nothing to act on is a way of not answering. But do not manufacture a problem where there is none: "keep" is a real verdict and a profile can deserve several of them.`;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return json({}, 200);

  const who = await caller(request);
  if (!who) return refuse(401, "not signed in");

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) {
    // Said out loud rather than passed over, the same as APNs. Until the key
    // exists the screen shows a plain "not available" rather than a spinner
    // that never resolves.
    console.warn("ANTHROPIC_API_KEY is not set; profile reviews are off");
    return refuse(503, "reviews are not available yet");
  }

  let body: ReviewRequest;
  try {
    body = await request.json();
  } catch {
    return refuse(400, "not a profile");
  }
  const shaped = shape(body);
  if (!shaped) return refuse(400, "not a profile");

  const db = admin();

  // Premium. The row is written only by the server after Apple has verified a
  // receipt, and no server does that yet -- so the check is real and the
  // enforcement waits, exactly as attestation does.
  const { data: sub } = await db
    .from("subscriptions")
    .select("expires_at")
    .eq("account_id", who.id)
    .maybeSingle();
  const subscribed = !!sub && new Date(sub.expires_at) > new Date();
  if (!subscribed) {
    if (isEnforced()) return refuse(402, "part of Arch Premium");
    console.warn(`premium not verified for ${who.id}; PREMIUM_ENFORCED is off`);
  }

  // The photographs, from the table and the bucket, never from the request. Only
  // the ones the profile actually shows: a rejected photograph is not on the
  // profile, and a review of it would be a review of something nobody sees.
  const { data: photoRows, error: photoError } = await db
    .from("photos")
    .select("position, storage_path")
    .eq("account_id", who.id)
    .eq("state", "approved")
    .not("uploaded_at", "is", null)
    .order("position", { ascending: true })
    .limit(PHOTO_LIMIT);
  if (photoError) return refuse(500, "could not read the photographs", photoError);

  const photos: { position: number; data: string }[] = [];
  for (const row of photoRows ?? []) {
    const { data: blob, error } = await db.storage.from("photos").download(row.storage_path);
    if (error || !blob) {
      console.error("photo unreadable", row.storage_path, error);
      continue;
    }
    photos.push({ position: row.position + 1, data: await toBase64(blob) });
  }

  if (photos.length === 0 && shaped.prompts.length === 0) {
    return refuse(400, "nothing to review yet");
  }

  // The digest is over what the reviewer will see, so a re-cropped photograph
  // or an edited word is a different profile and a stored note does not outlive
  // the thing it was about.
  const hash = await digest(
    JSON.stringify({
      words: shaped,
      photos: photos.map((p) => [p.position, p.data.length, p.data.slice(0, 64), p.data.slice(-64)]),
    }),
  );

  if (!shaped.fresh) {
    const { data: stored } = await db
      .from("profile_reviews")
      .select("notes, model, created_at")
      .eq("account_id", who.id)
      .eq("profile_hash", hash)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (stored) {
      return json({ status: "ok", notes: stored.notes, model: stored.model, createdAt: stored.created_at, stored: true });
    }
  }

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await db
    .from("profile_reviews")
    .select("id", { count: "exact", head: true })
    .eq("account_id", who.id)
    .gte("created_at", since);
  if ((count ?? 0) >= REVIEWS_PER_DAY) {
    return refuse(429, "that is enough reviews for one day");
  }

  const client = new Anthropic({ apiKey: key });

  const content: Anthropic.ContentBlockParam[] = [];
  for (const photo of photos) {
    content.push({ type: "text", text: `Photo ${photo.position}:` });
    content.push({
      type: "image",
      source: { type: "base64", media_type: "image/jpeg", data: photo.data },
    });
  }
  content.push({ type: "text", text: describe(shaped, photos.length) });

  let response: Anthropic.Message;
  try {
    response = await client.messages.create({
      model: MODEL,
      max_tokens: 8000,
      // Adaptive thinking is the model's default. Medium effort: this is a
      // careful read of six photographs and three paragraphs, not a proof, and
      // the person is looking at a spinner.
      output_config: {
        effort: "medium",
        format: { type: "json_schema", schema: NOTES_SCHEMA },
      },
      system: [{ type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content }],
    });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) {
      return refuse(429, "busy just now", error);
    }
    if (error instanceof Anthropic.APIError) {
      return refuse(502, "the reviewer could not answer", `${error.status} ${error.message}`);
    }
    return refuse(502, "the reviewer could not answer", error);
  }

  if (response.stop_reason === "refusal") {
    // Rare for a profile, and worth knowing about when it happens. The reader
    // gets the same plain sentence as any other failure; the category is logged.
    console.error("review refused", response.stop_details);
    return refuse(422, "the reviewer could not answer this profile");
  }
  if (response.stop_reason === "max_tokens") {
    return refuse(502, "the reviewer ran out of room", response.usage);
  }

  const text = response.content.find((b) => b.type === "text");
  if (!text || text.type !== "text") return refuse(502, "the reviewer said nothing");

  let notes: unknown;
  try {
    notes = JSON.parse(text.text);
  } catch (error) {
    return refuse(502, "the reviewer answered in the wrong shape", error);
  }

  const { error: writeError } = await db.from("profile_reviews").insert({
    account_id: who.id,
    profile_hash: hash,
    notes,
    model: response.model,
  });
  // A note that could not be stored is still a note. The reader gets it; the
  // next open costs a second call, which is the lesser problem.
  if (writeError) console.error("could not store the review", writeError);

  console.log(
    `review for ${who.id}: ${photos.length} photos, ${shaped.prompts.length} answers, ` +
      `${response.usage.input_tokens} in (${response.usage.cache_read_input_tokens ?? 0} cached), ` +
      `${response.usage.output_tokens} out`,
  );

  return json({ status: "ok", notes, model: response.model, createdAt: new Date().toISOString(), stored: false });
});

/** The request, clipped to the profile's own limits, or null if it is not one. */
function shape(raw: unknown): ReviewRequest | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const prompts = Array.isArray(r.prompts) ? r.prompts : [];
  const interests = Array.isArray(r.interests) ? r.interests : [];
  const clean = (s: unknown, limit: number) =>
    typeof s === "string" ? s.trim().slice(0, limit) : "";
  return {
    name: clean(r.name, 40) || undefined,
    age: typeof r.age === "number" && r.age >= 18 && r.age <= 120 ? r.age : undefined,
    work: clean(r.work, 60) || undefined,
    prompts: prompts
      .slice(0, MAX_PROMPTS)
      .map((p) => ({
        question: clean((p as Record<string, unknown>)?.question, 120),
        answer: clean((p as Record<string, unknown>)?.answer, ANSWER_LIMIT),
      }))
      .filter((p) => p.question && p.answer),
    interests: interests.slice(0, MAX_INTERESTS).map((t) => clean(t, 40)).filter(Boolean),
    fresh: r.fresh === true,
  };
}

/** The words, laid out for the reviewer after the photographs. */
function describe(p: ReviewRequest, photoCount: number): string {
  const lines: string[] = [];
  const details = [p.name, p.age ? `${p.age}` : "", p.work].filter(Boolean).join(", ");
  if (details) lines.push(`About them: ${details}.`);
  lines.push(photoCount === 0
    ? "There are no photographs on the profile yet."
    : `${photoCount} ${photoCount === 1 ? "photograph" : "photographs"}, numbered above in the order the profile shows them.`);
  if (p.prompts.length) {
    lines.push("", "Answers:");
    p.prompts.forEach((q, i) => {
      lines.push(`Answer ${i + 1}. ${q.question}`, `"${q.answer}"`, "");
    });
  } else {
    lines.push("No written answers yet.");
  }
  if (p.interests.length) lines.push(`Interests: ${p.interests.join(", ")}.`);
  lines.push(
    "",
    "Give one note per photograph and one per answer, then the overall paragraph. Position numbers match the numbering above.",
  );
  return lines.join("\n");
}

async function toBase64(blob: Blob): Promise<string> {
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let raw = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    raw += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(raw);
}

async function digest(text: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
