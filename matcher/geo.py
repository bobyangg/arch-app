# -*- coding: utf-8 -*-
"""Distance, the way the app does it.

Two things here are easy to get subtly wrong and both would quietly invent a
result, so they are written once and tested in `selftest.py`:

* **Rounding.** Swift's `.rounded()` is half *away from zero*. Python's `round()`
  is half *to even*. Every stored coordinate goes through it, and Beacon sits
  exactly on the boundary.
* **The mutual radius test.** A person whose slider is at "Anywhere" imposes no
  constraint at all, so the test is not `d <= min(a, b)`.
"""
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLACES = os.path.join(ROOT, "Arch", "Mock", "PlaceLibrary.swift")

#: `Coordinate.grid` -- a little over a kilometre.
GRID = 0.01
#: `Coordinate.miles(to:)`.
EARTH_RADIUS = 3958.8
#: `SettingsStore.isUnlimited`. At or above this the slider reads "Anywhere".
UNLIMITED = 100


def round_half_away(x):
    """Swift's `.rounded()`: 0.5 goes away from zero, not to even.

    Python's built-in disagrees on exactly the values that land on a boundary,
    which is where a coordinate library puts its towns.
    """
    return math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)


def coarsen(latitude, longitude):
    """`Coordinate.coarsened`. Everything stored goes through this."""
    return (
        round_half_away(latitude / GRID) * GRID,
        round_half_away(longitude / GRID) * GRID,
    )


def miles(a, b):
    """Great-circle miles between two (lat, lon) pairs, by haversine."""
    lat1, lon1 = a
    lat2, lon2 = b
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS * math.atan2(math.sqrt(h), math.sqrt(1 - h))


def is_unlimited(radius):
    return radius >= UNLIMITED


def within(distance, radius_a, radius_b):
    """Does this distance satisfy *both* people?

    Not `distance <= min(radius_a, radius_b)`. "Anywhere" means no filter, and
    `min` would silently clamp such a person to a 100-mile circle -- which puts
    Hudson (108 miles from Fort Greene) out of everybody's reach and hands back a
    starvation catastrophe that the settings never actually caused.
    """
    if not is_unlimited(radius_a) and distance > radius_a:
        return False
    if not is_unlimited(radius_b) and distance > radius_b:
        return False
    return True


class Place(object):
    """One entry from `PlaceLibrary.all`, already coarsened."""

    __slots__ = ("id", "name", "city", "lat", "lon")

    def __init__(self, id, name, city, lat, lon):
        self.id = id
        self.name = name
        self.city = city
        self.lat = lat
        self.lon = lon

    @property
    def point(self):
        return (self.lat, self.lon)

    def __repr__(self):
        return "Place(%s, %s)" % (self.name, self.city)


def load_places():
    """Parsed out of the Swift, for the same reason the tables are.

    The literals in `PlaceLibrary` are *not* what the app holds -- `place()`
    coarsens on construction, so 31 of the 32 differ from what is written down.
    Coarsening here reproduces the stored value rather than the typed one.
    """
    with open(PLACES, encoding="utf-8") as handle:
        source = handle.read()
    pattern = re.compile(
        r'place\("([a-z0-9-]+)", "([^"]+)", "([^"]+)", (-?[0-9.]+), (-?[0-9.]+)\)'
    )
    places = []
    for pid, name, city, lat, lon in pattern.findall(source):
        lat, lon = coarsen(float(lat), float(lon))
        places.append(Place(pid, name, city, lat, lon))
    assert len(places) == 32, len(places)
    return places


PLACE_LIST = load_places()
BY_ID = {p.id: p for p in PLACE_LIST}
