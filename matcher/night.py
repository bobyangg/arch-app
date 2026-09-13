# -*- coding: utf-8 -*-
"""Seven mornings in a row.

One night tells you almost nothing. A person with no matches on Tuesday is
unremarkable; the same person with no matches all week is the failure that matters,
and it only becomes visible by running the thing repeatedly with the slots carrying
over.

**Dismissal is one-sided on purpose.** If A dismisses B and B lost A from their
roster at the same moment, B would learn they had been dismissed -- which is the one
thing the product promises never to reveal. So a dismissal opens the dismisser's
slot and leaves the other roster untouched. Messaging is different: the app says
outright that writing to somebody takes them out of your roster and takes you out of
theirs, so a message dissolves the pair at both ends.
"""
import random

import match


class State(object):
    """One person's standing across the week."""

    __slots__ = ("pid", "roster", "open_convs", "seen", "empty_nights", "met")

    def __init__(self, pid):
        self.pid = pid
        self.roster = set()
        self.open_convs = 0
        self.seen = {}
        self.empty_nights = 0
        self.met = set()


class Result(object):
    def __init__(self, cfg, people):
        self.cfg = cfg
        self.people = people
        self.by_id = dict((p.pid, p) for p in people)
        self.nights = []          # per night: dict of stats
        self.states = {}
        self.pair_scores = []     # every delivered pair's score, all nights


def is_held(person, state, cfg):
    """A roster with too many open conversations waits instead of refilling.

    This is the policy working, not a matching failure, so the report counts these
    separately -- folding them into the starvation number would make a deliberate
    product decision look like a bug.
    """
    limit = 15 if person.premium else 10
    return state.open_convs >= limit


def run(people, graph, cfg, seed, scorer=None):
    """The whole week. Returns a `Result`."""
    rng = random.Random(seed + 77)
    result = Result(cfg, people)
    states = dict((p.pid, State(p.pid)) for p in people)
    result.states = states
    by_id = result.by_id

    for night in range(1, cfg.nights + 1):
        need = {}
        held = set()
        for p in people:
            st = states[p.pid]
            if p.paused:
                need[p.pid] = 0
                continue
            if is_held(p, st, cfg):
                need[p.pid] = 0
                held.add(p.pid)
                continue
            need[p.pid] = max(0, p.capacity - len(st.roster))

        pairs, filled = match.match_night(
            graph, need, dict((pid, states[pid].seen) for pid in states),
            night, cfg, seed, scorer=scorer,
        )

        for a, b in pairs:
            states[a].roster.add(b)
            states[b].roster.add(a)
            states[a].seen[b] = night
            states[b].seen[a] = night
            states[a].met.add(b)
            states[b].met.add(a)

        # What the roster looks like once the night's pairing has landed.
        sizes = {}
        for p in people:
            st = states[p.pid]
            sizes[p.pid] = len(st.roster)
            if not p.paused and p.pid not in held and not st.roster:
                st.empty_nights += 1

        result.pair_scores.extend(
            [_edge_score(graph, a, b) for a, b in pairs]
        )
        result.nights.append({
            "night": night,
            "pairs": list(pairs),
            "filled": dict(filled),
            "sizes": sizes,
            "held": set(held),
            "need": dict(need),
        })

        _between(people, states, by_id, cfg, rng)

    return result


def _edge_score(graph, a, b):
    for s, other in graph[a]:
        if other == b:
            return s
    return 0.0


def _between(people, states, by_id, cfg, rng):
    """What happens during the day.

    Resolved per pair rather than per person, so that a mutual outcome is not
    counted twice and a message does not race a dismissal.
    """
    resolved = set()
    for p in people:
        st = states[p.pid]
        for other in list(st.roster):
            key = (p.pid, other) if p.pid < other else (other, p.pid)
            if key in resolved:
                continue
            resolved.add(key)
            other_st = states[other]

            a_writes = rng.random() < cfg.p_message
            b_writes = rng.random() < cfg.p_message
            if a_writes or b_writes:
                # Writing takes them out of your roster and you out of theirs.
                st.roster.discard(other)
                other_st.roster.discard(p.pid)
                sender, recipient = (st, other_st) if a_writes else (other_st, st)
                sender.open_convs += 1
                if rng.random() < cfg.p_accept:
                    recipient.open_convs += 1
                continue

            # One-sided: the other person is never told, and keeps their slot.
            if rng.random() < cfg.p_dismiss:
                st.roster.discard(other)
            if rng.random() < cfg.p_dismiss:
                other_st.roster.discard(p.pid)

    for st in states.values():
        for _ in range(st.open_convs):
            if rng.random() < cfg.p_leave:
                st.open_convs -= 1
