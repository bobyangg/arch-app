# -*- coding: utf-8 -*-
"""The 95 numbers, read out of the Swift rather than retyped.

`Arch/Mock/Compatibility.swift` is the single source of truth. If the tables lived
in two places they would drift, and the entire point of this program is to test
*those* numbers rather than a copy of them that has quietly diverged.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPATIBILITY = os.path.join(ROOT, "Arch", "Mock", "Compatibility.swift")
QUESTIONNAIRE = os.path.join(ROOT, "Arch", "Mock", "Questionnaire.swift")


def _read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def load_questions():
    """[(id, options, rule)] in the order the questionnaire asks them."""
    source = _read(QUESTIONNAIRE)
    questions = []
    pattern = re.compile(
        r'\.init\(id: "(q\d+)",\s*\n\s*text: "(.*?)",\s*\n\s*'
        r'options: \[(.*?)\],\s*\n\s*axis: "(\w+)", rule: \.(\w+)\)',
        re.S,
    )
    for match in pattern.finditer(source):
        qid, text, options, axis, rule = match.groups()
        questions.append(
            {
                "id": qid,
                "text": text,
                "options": re.findall(r'"(.*?)"', options),
                "axis": axis,
                "rule": rule,
            }
        )
    assert len(questions) == 16, len(questions)
    return questions


def load_tables():
    """{question id: {"weight": float, "grid": [[float]]}} for the scored questions."""
    source = _read(COMPATIBILITY)
    tables = {}
    pattern = re.compile(
        r'CompatibilityTable\(questionID: "(q\d+)", weight: ([\d.]+), grid: \[(.*?)\n    \]\)',
        re.S,
    )
    for qid, weight, body in pattern.findall(source):
        grid = [
            [float(value) for value in re.findall(r"\d\.\d\d", line)]
            for line in body.splitlines()
            if re.findall(r"\d\.\d\d", line)
        ]
        tables[qid] = {"weight": float(weight), "grid": grid}
    assert len(tables) == 13, len(tables)
    return tables


def load_requirements():
    """{question id: [[bool]]} — the filters, parsed out of the `Requirement` enum."""
    source = _read(COMPATIBILITY)
    names = {"children": "q14", "exclusivity": "q15", "location": "q16"}
    requirements = {}
    for name, qid in names.items():
        match = re.search(
            r"static let %s = \[(.*?)\n        \]" % name, source, re.S
        )
        assert match, name
        grid = [
            [word == "true" for word in re.findall(r"\b(true|false)\b", line)]
            for line in match.group(1).splitlines()
            if re.findall(r"\b(?:true|false)\b", line)
        ]
        requirements[qid] = grid
    return requirements


def check(tables, questions):
    """Square, symmetric, in range, and the right size — the same checks
    `Compatibility.isConsistent` makes, run before anything relies on them."""
    sizes = {q["id"]: len(q["options"]) for q in questions}
    problems = []
    for qid, table in tables.items():
        n = sizes[qid]
        grid = table["grid"]
        if len(grid) != n:
            problems.append("%s has %d rows, needs %d" % (qid, len(grid), n))
            continue
        for i in range(n):
            if len(grid[i]) != n:
                problems.append("%s row %d has %d values" % (qid, i, len(grid[i])))
                continue
            for j in range(n):
                if not 0.0 <= grid[i][j] <= 1.0:
                    problems.append("%s[%d][%d] out of range" % (qid, i, j))
                if grid[i][j] != grid[j][i]:
                    problems.append("%s asymmetric at [%d][%d]" % (qid, i, j))
    return problems


TABLES = load_tables()
QUESTIONS = load_questions()
REQUIREMENTS = load_requirements()
SCORED = [q for q in QUESTIONS if q["rule"] != "requirement"]

# Checked at import, not on request. A transposed digit in the Swift is the exact
# failure this module exists to catch, and a check nobody calls catches nothing.
_PROBLEMS = check(TABLES, QUESTIONS)
if _PROBLEMS:
    raise SystemExit("Compatibility.swift is inconsistent:" + "".join(
        '\n  ' + p for p in _PROBLEMS))

#: What the weights sum to. Advertised as the ceiling; it is not one.
MAX_SCORE = sum(t["weight"] for t in TABLES.values())

#: What a pair can actually score.
#:
#: Every question is independent, so the best attainable total is the sum of each
#: grid's own best cell -- and `q6` has no 1.00 cell, so nobody reaches MAX_SCORE.
#: Reporting a percentage of 13 squashes the real working range into a narrow band
#: near 77% and makes perfectly good tables look like noise. Use `normalise`.
ATTAINABLE_MAX = sum(t["weight"] * max(max(r) for r in t["grid"]) for t in TABLES.values())
ATTAINABLE_MIN = sum(t["weight"] * min(min(r) for r in t["grid"]) for t in TABLES.values())


def normalise(total):
    """A raw score as 0-1 across the range pairs can actually occupy."""
    span = ATTAINABLE_MAX - ATTAINABLE_MIN
    return max(0.0, min(1.0, (total - ATTAINABLE_MIN) / span))


def score(a_answers, b_answers):
    """Two people's answers as one number. Higher is better; the ceiling is 13."""
    total = 0.0
    for qid, table in TABLES.items():
        i, j = a_answers[qid], b_answers[qid]
        total += table["weight"] * table["grid"][i][j]
    return total


def meets_requirements(a_answers, b_answers):
    """Children, exclusivity, location. A filter, never a weight — the moment a
    good score can buy its way past one, those questions stop meaning anything."""
    for qid, grid in REQUIREMENTS.items():
        if not grid[a_answers[qid]][b_answers[qid]]:
            return False
    return True
