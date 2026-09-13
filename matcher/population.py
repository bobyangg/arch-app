# -*- coding: utf-8 -*-
"""Inventing a city full of people to match.

**The generator decides the answer, so it is written to be arguable rather than
convenient.** Two failure modes, in opposite directions:

* Draw every answer uniformly at random and nobody resembles anybody. Real
  populations cluster -- people who recharge alone also tend to want the quiet
  Friday -- and a uniform crowd would make good tables look like they separate
  nothing. A false negative.
* Draw everyone from a handful of crisp archetypes and the pool is full of near
  clones, where *any* scoring rule picks the same people. A false positive.

So: `archetypes` latent types, `noise` as the chance a given answer is resampled
instead of inherited, and `rand_frac` of people drawn with no type at all. The
honest reading of the result is the one that survives the noise sweep.

**The draws are arranged so that changing `noise` changes nothing else.** Every
person gets their uniform draw and their replacement answer up front, from streams
that never see `noise`; the parameter only moves a threshold. Without that, each
rung of the sweep is a different city and the sweep measures weather.
"""
import random

import geo
import tables

#: Scored question ids, in the order the questionnaire asks them.
SCORED_IDS = [q["id"] for q in tables.QUESTIONS if q["rule"] != "requirement"]
#: The three that filter instead.
REQ_IDS = [q["id"] for q in tables.QUESTIONS if q["rule"] == "requirement"]
OPTIONS = {q["id"]: len(q["options"]) for q in tables.QUESTIONS}

GENDERS = ("man", "woman", "nonBinary")

#: Marginals for the requirement questions, drawn *independently* of the scored
#: latent. If wanting children rode the same archetype as how you argue, the hard
#: filters would delete low-scoring pairs for free and every discrimination number
#: in the report would be inflated by the filtering rather than the tables.
REQ_MARGINALS = {
    "q14": (0.45, 0.20, 0.20, 0.15),   # Yes / No / Open to it / Still working it out
    "q15": (0.85, 0.07, 0.08),         # One at a time / No / Still working it out
    "q16": (0.50, 0.20, 0.30),         # Yes / No / Depends who I am with
}

#: The distance slider. 100 is "Anywhere" and means no filter at all.
DISTANCE_CHOICES = ((10, 0.60), (25, 0.20), (50, 0.12), (100, 0.08))

#: Roughly the real shape of the place library, with the three upstate towns held
#: near 6% -- enough that a starving rural cohort is a cohort and not an anecdote.
CITY_WEIGHTS = {
    "Brooklyn": 0.34,
    "Queens": 0.18,
    "Manhattan": 0.24,
    "The Bronx": 0.08,
    "Staten Island": 0.04,
    "New Jersey": 0.06,
    "New York": 0.06,
}


class Config(object):
    """Everything the report has to print back in its header."""

    def __init__(self, **kw):
        self.n = 600
        self.archetypes = 6
        self.noise = 0.30
        self.rand_frac = 0.15
        self.nights = 7
        self.cooldown = 7
        self.premium_rate = 0.12
        self.paused_rate = 0.04
        self.block_rate = 0.004
        self.fill = "off"
        self.age_asymmetry = False
        self.seed = 20260912
        # Between-night behaviour, per person per roster-mate.
        self.p_dismiss = 0.22
        self.p_message = 0.14
        self.p_accept = 0.55
        self.p_leave = 0.06
        for k, v in kw.items():
            if not hasattr(self, k):
                raise KeyError(k)
            setattr(self, k, v)

    def items(self):
        return sorted(self.__dict__.items())


class Person(object):
    __slots__ = (
        "pid", "gender", "seeking", "age", "min_age", "max_age",
        "lat", "lon", "place", "distance", "premium", "paused",
        "blocks", "answers", "reqs", "archetype",
    )

    def __init__(self, **kw):
        for k, v in kw.items():
            setattr(self, k, v)

    @property
    def capacity(self):
        return 7 if self.premium else 5

    @property
    def point(self):
        return (self.lat, self.lon)

    def answer_dict(self):
        """The shape `tables.score` wants. For cross-checking, not for the loop."""
        d = dict(zip(SCORED_IDS, self.answers))
        d.update(zip(REQ_IDS, self.reqs))
        return d

    def __repr__(self):
        return "<%s %s %d>" % (self.pid, self.gender, self.age)


def _pick(rng, choices):
    """choices is a sequence of (value, weight)."""
    r = rng.random() * sum(w for _, w in choices)
    for value, weight in choices:
        r -= weight
        if r <= 0:
            return value
    return choices[-1][0]


def _draw_gender(rng):
    return _pick(rng, (("man", 0.48), ("woman", 0.48), ("nonBinary", 0.04)))


def _draw_seeking(rng, gender):
    """Who somebody wants to meet.

    Kept deliberately plain: a large straight majority, a small same-gender group,
    and a bisexual group who are most of the reason the non-binary cohort has
    anybody to meet at all. Orientation is the largest filter in the funnel, so the
    shape being roughly right matters more than it being exactly right.
    """
    if gender == "nonBinary":
        picked = set(g for g in GENDERS if rng.random() < 0.6)
        return frozenset(picked or {rng.choice(GENDERS)})
    other = "woman" if gender == "man" else "man"
    roll = rng.random()
    if roll < 0.78:
        seeking = {other}
    elif roll < 0.85:
        seeking = {gender}
    else:
        seeking = {"man", "woman"}
    if rng.random() < 0.18:
        seeking.add("nonBinary")
    return frozenset(seeking)


def _draw_age(rng):
    age = int(round(rng.gauss(30.5, 5.6)))
    return max(21, min(52, age))


def _draw_age_prefs(rng, age, asymmetric):
    """What ages somebody will consider.

    Symmetric by default -- a window around your own age. `age_asymmetry` turns on
    the real-world pattern where the window drifts downward, which is the largest
    single driver of an age-stranded cohort. Off by default, because turning it on
    by default would be assuming the finding.
    """
    low = age - rng.randint(2, 8)
    high = age + rng.randint(2, 10)
    if asymmetric:
        low -= rng.randint(0, 4)
        high -= rng.randint(0, 4)
    return max(18, min(70, low)), max(18, min(70, high))


def _draw_place(rng, places_by_city):
    city = _pick(rng, tuple(CITY_WEIGHTS.items()))
    return rng.choice(places_by_city[city])


def build(cfg, seed=None):
    """A whole city. Deterministic given the seed."""
    seed = cfg.seed if seed is None else seed
    rng_demo = random.Random(seed + 11)
    rng_geo = random.Random(seed + 22)
    rng_arch = random.Random(seed + 33)
    rng_draw = random.Random(seed + 44)
    rng_req = random.Random(seed + 55)

    places_by_city = {}
    for p in geo.PLACE_LIST:
        places_by_city.setdefault(p.city, []).append(p)

    # The latent types, and who belongs to which. Both fixed across a noise sweep.
    archetypes = [
        tuple(rng_arch.randrange(OPTIONS[q]) for q in SCORED_IDS)
        for _ in range(cfg.archetypes)
    ]

    people = []
    for i in range(cfg.n):
        which = rng_arch.randrange(cfg.archetypes)
        untyped = rng_arch.random() < cfg.rand_frac

        # Drawn before `noise` is consulted, so the sweep varies one thing only.
        rolls = [rng_draw.random() for _ in SCORED_IDS]
        replacements = [rng_draw.randrange(OPTIONS[q]) for q in SCORED_IDS]
        answers = tuple(
            replacements[j] if (untyped or rolls[j] < cfg.noise) else archetypes[which][j]
            for j in range(len(SCORED_IDS))
        )
        reqs = tuple(
            _pick(rng_req, tuple(enumerate(REQ_MARGINALS[q]))) for q in REQ_IDS
        )

        gender = _draw_gender(rng_demo)
        age = _draw_age(rng_demo)
        low, high = _draw_age_prefs(rng_demo, age, cfg.age_asymmetry)
        place = _draw_place(rng_geo, places_by_city)

        people.append(Person(
            pid="p%03d" % i,
            gender=gender,
            seeking=_draw_seeking(rng_demo, gender),
            age=age,
            min_age=low,
            max_age=high,
            lat=place.lat,
            lon=place.lon,
            place=place,
            distance=_pick(rng_geo, DISTANCE_CHOICES),
            premium=rng_demo.random() < cfg.premium_rate,
            paused=rng_demo.random() < cfg.paused_rate,
            blocks=set(),
            answers=answers,
            reqs=reqs,
            archetype=None if untyped else which,
        ))

    # A sprinkling of blocks, so the filter is exercised rather than assumed.
    for p in people:
        for _ in range(2):
            if rng_demo.random() < cfg.block_rate * 2:
                p.blocks.add(rng_demo.choice(people).pid)

    return people
