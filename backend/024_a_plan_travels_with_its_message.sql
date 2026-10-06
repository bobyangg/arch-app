-- A plan from the Date planner, carried with the message that shares it.
--
-- The planner lays out a date -- three stops, their times, how you get between
-- them -- and "Share this plan" sends it into a conversation. The words go in
-- `body` as they always have: "How about this?" and a line per stop. That is what
-- a push notification shows, and what a build that predates the planner draws,
-- so nothing that reads messages today has to change.
--
-- What `body` cannot carry is the structure: which stops, in what order, at what
-- time, and -- for an answer -- which plan it answers. That goes here, so the
-- thread can draw the plan as a card the other person can say yes to, rather
-- than as a paragraph they have to parse.
--
-- Two shapes, both written by the client:
--
--   a plan    {"time": "afternoon", "stops": [{"start": 840, "name": ...,
--              "kind": ..., "neighbourhood": ..., "travel": ..., "reason": ...}]}
--   an answer {"answering": "<id of the message whose plan this answers>"}
--
-- **Nothing new is visible to anybody.** The column is on `messages`, so it is
-- read and written under the policies that already decide who can read and
-- write a message: the two people in the conversation, and the sender only. A
-- plan never names a coordinate -- a stop is a name and a neighbourhood -- and
-- the client leaves out the reasons ("Yusuf wrote ...") when a plan is shared
-- with anybody other than the person it was made with.
--
-- Bounded, because it is client-written: an object, and no bigger than twice the
-- longest body a message may have.

alter table messages
    add column plan jsonb
    check (plan is null or (jsonb_typeof(plan) = 'object' and length(plan::text) <= 8000));

comment on column messages.plan is
    'A Date planner plan, or an answer to one. Null for every ordinary message.';
