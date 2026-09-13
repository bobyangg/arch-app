# -*- coding: utf-8 -*-
"""Check the schema without a Postgres to run it against.

There is no database on this machine, so these files have the same problem the
Swift has: written carefully, never executed. `sqlparse` only tokenises -- it will
happily accept a foreign key to a table that does not exist -- so the checks that
matter here are cross-referential:

    every referenced table exists
    every referenced column exists
    every enum used as a column type was created
    every function called in a policy was defined
    every policy and every index names a real table
    parentheses and dollar-quotes balance

That will not catch a wrong operator or a subtly bad policy, but it catches the
whole class of mistake that comes from typing a name twice.

    python lint.py
"""
import os
import re
import sys

import sqlparse

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = ["001_schema.sql", "002_policies.sql", "003_functions.sql"]

problems = []
notes = []


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as handle:
        return handle.read()


source = ""
for name in FILES:
    source += read(name) + "\n"


def strip_comments(text):
    text = re.sub(r"--[^\n]*", "", text)
    return re.sub(r"/\*.*?\*/", "", text, flags=re.S)


clean = strip_comments(source)


# ------------------------------------------------------------------ inventory

TYPES = set(re.findall(r"create type\s+(\w+)\s+as enum", clean, re.I))
FUNCTIONS = set(re.findall(r"create or replace function\s+(\w+)\s*\(", clean, re.I))
VIEWS = set(re.findall(r"create or replace view\s+(\w+)", clean, re.I))

BUILTIN = {
    "uuid", "text", "boolean", "date", "timestamptz", "bytea", "bigint", "real",
    "smallint", "int", "integer", "numeric", "serial", "jsonb", "float",
}

TABLES = {}


def parse_tables(text):
    """{table: [column names]} plus the raw body, for the reference checks."""
    for match in re.finditer(r"create table\s+(\w+)\s*\((.*?)\n\);", text, re.S | re.I):
        name, body = match.group(1), match.group(2)
        columns = []
        declared = []
        depth = 0
        for raw in body.split("\n"):
            line = raw.strip()
            if not line:
                continue
            # Only a line that begins at depth 0 declares anything. A continuation
            # of a multi-line CHECK sits at depth > 0, and reading it as a column
            # turns "and coarse_lat = ..." into a column called `and`.
            if depth == 0:
                m = re.match(r"(\w+)\s+([\w\[\]]+)", line)
                if m and m.group(1).lower() not in (
                    "constraint", "primary", "unique", "foreign", "check", "exclude"
                ):
                    columns.append(m.group(1))
                    declared.append((m.group(1), m.group(2)))
            depth += line.count("(") - line.count(")")
        TABLES[name] = {"columns": columns, "declared": declared, "body": body}


parse_tables(clean)


# -------------------------------------------------------------------- checks

def check(condition, message):
    if not condition:
        problems.append(message)


# 1. Balanced parentheses and dollar-quotes, per file.
for name in FILES:
    text = strip_comments(read(name))
    check(text.count("(") == text.count(")"),
          "%s: unbalanced parentheses (%d open, %d close)"
          % (name, text.count("("), text.count(")")))
    check(text.count("$$") % 2 == 0,
          "%s: unbalanced dollar-quotes (%d)" % (name, text.count("$$")))
    check("'" not in re.sub(r"'[^']*'", "", text),
          "%s: unterminated string literal" % name)

# 2. Foreign keys point at tables and columns that exist.
for table, info in TABLES.items():
    for target, column in re.findall(r"references\s+(?:auth\.)?(\w+)\s*\((\w+)\)",
                                     info["body"], re.I):
        if target in ("users",):          # Supabase's own auth.users
            continue
        check(target in TABLES,
              "%s: foreign key to unknown table '%s'" % (table, target))
        if target in TABLES:
            check(column in TABLES[target]["columns"],
                  "%s: foreign key to %s(%s), which is not a column"
                  % (table, target, column))

# 3. Column types are either builtin or an enum that was created.
for table, info in TABLES.items():
    for col, raw in info["declared"]:
        typ = raw.lower()
        if typ in BUILTIN or typ in TYPES or typ.rstrip("[]") in TYPES:
            continue
        problems.append("%s.%s: unknown type '%s'" % (table, col, raw))

# 4. Every table named by a policy, an index, an ALTER or a trigger exists.
for stmt, table in re.findall(r"(alter table)\s+(\w+)", clean, re.I):
    check(table in TABLES, "alter table names unknown table '%s'" % table)
for table in re.findall(r"create policy\s+\w+\s+on\s+(\w+)", clean, re.I):
    check(table in TABLES, "policy names unknown table '%s'" % table)
for table in re.findall(r"create index\s+\w+\s+on\s+(\w+)", clean, re.I):
    check(table in TABLES, "index names unknown table '%s'" % table)
for table in re.findall(r"create trigger\s+\w+\s+\w+\s+update on\s+(\w+)", clean, re.I):
    check(table in TABLES, "trigger names unknown table '%s'" % table)

# 5. Indexed columns exist.
for table, cols in re.findall(r"create index\s+\w+\s+on\s+(\w+)\s*\(([^)]*)\)",
                              clean, re.I):
    if table not in TABLES:
        continue
    for col in cols.split(","):
        col = col.strip().split()[0]
        check(col in TABLES[table]["columns"],
              "index on %s names unknown column '%s'" % (table, col))

# 6. Functions called inside policies were defined.
called = set(re.findall(r"\b(arch_\w+)\s*\(", clean))
for fn in called:
    check(fn in FUNCTIONS, "policy calls undefined function '%s'" % fn)

# 7. Triggers call a function that exists.
for fn in re.findall(r"execute function\s+(\w+)\s*\(", clean, re.I):
    check(fn in FUNCTIONS or fn == "touch_updated_at",
          "trigger calls undefined function '%s'" % fn)

# 8. Columns named in the view exist on the table it selects from.
for match in re.finditer(r"create or replace view\s+(\w+).*?from\s+(\w+)\s+(\w+)",
                         clean, re.S | re.I):
    view, table, alias = match.groups()
    if table not in TABLES:
        problems.append("view %s selects from unknown table '%s'" % (view, table))
        continue
    body = clean[match.start():match.end()]
    for col in re.findall(r"\b%s\.(\w+)" % alias, body):
        check(col in TABLES[table]["columns"],
              "view %s selects %s.%s, which is not a column" % (view, table, col))

# 9. Every table has RLS switched on. A table that is merely forgotten is
#    readable by anybody with the anon key, which is the whole risk.
rls = set(re.findall(r"alter table\s+(\w+)\s+enable row level security", clean, re.I))
for table in TABLES:
    check(table in rls, "%s: row level security is never enabled" % table)

# 10. Every table with RLS on has at least one policy, or is deliberately sealed.
SEALED = {"device_bits"}
policed = set(re.findall(r"create policy\s+\w+\s+on\s+(\w+)", clean, re.I))
for table in rls:
    if table not in policed and table not in SEALED:
        notes.append("%s: RLS on and no policy -- nothing can read it" % table)


# 11. `insert into t (a, b, c)` names real columns, and the VALUES list is the
#     same length. Column order against a SELECT is not checkable by name -- an
#     insert whose select list is in the wrong order is perfectly well-formed --
#     but a count mismatch is the cheap half of that bug and worth catching.
for table, cols, values in re.findall(
        r"insert into\s+(\w+)\s*\(([^)]*)\)\s*values\s*\(([^;]*?)\)\s*(?:on conflict|returning|;)",
        clean, re.I | re.S):
    if table not in TABLES:
        check(False, "insert into unknown table '%s'" % table)
        continue
    names = [c.strip() for c in cols.split(",") if c.strip()]
    for col in names:
        check(col in TABLES[table]["columns"],
              "insert into %s names unknown column '%s'" % (table, col))
    # Only count when the VALUES list has no nested call that could hide a comma.
    if "(" not in values:
        supplied = len([v for v in values.split(",") if v.strip()])
        check(supplied == len(names),
              "insert into %s lists %d columns but supplies %d values"
              % (table, len(names), supplied))

for table, cols in re.findall(r"insert into\s+(\w+)\s*\(([^)]*)\)\s*select",
                              clean, re.I):
    if table not in TABLES:
        continue
    for col in [c.strip() for c in cols.split(",") if c.strip()]:
        check(col in TABLES[table]["columns"],
              "insert into %s names unknown column '%s'" % (table, col))


# -------------------------------------------------------------------- report

statements = [s for s in sqlparse.split(source) if s.strip()]

print("=" * 64)
print("schema lint")
print("=" * 64)
print("  files          %s" % ", ".join(FILES))
print("  statements     %d" % len(statements))
print("  tables         %d" % len(TABLES))
print("  enum types     %d" % len(TYPES))
print("  functions      %d" % len(FUNCTIONS))
print("  views          %d" % len(VIEWS))
print("  columns        %d" % sum(len(t["columns"]) for t in TABLES.values()))
print("  RLS enabled    %d of %d tables" % (len(rls), len(TABLES)))
print("  policies       %d" % len(re.findall(r"create policy", clean, re.I)))
print()

for note in notes:
    print("  note:  %s" % note)
if notes:
    print()

if problems:
    print("  %d problem(s):" % len(problems))
    for p in problems:
        print("    - %s" % p)
    sys.exit(1)

print("  no cross-reference problems found.")
print()
print("  This is a linter, not a database. It proves every name resolves; it does")
print("  not prove a policy is correct. The policies still need running against a")
print("  real Postgres with two accounts and a deliberate attempt to read what")
print("  should be unreadable.")
sys.exit(0)
