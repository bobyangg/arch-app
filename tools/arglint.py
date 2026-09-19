"""Argument order and labels, for this project's own structs.

`swiftcheck.py` says in its own output that it checks nothing but whether names
resolve -- not types, not argument labels, not order. That gap has now cost two
twenty-minute round trips to the same mistake:

    error: argument 'locationNote' must precede argument 'onCancel'
    error: argument 'onAccept' must precede argument 'popToRoot'

Both are the same thing. A struct's memberwise initialiser takes its arguments
in *declaration* order, so adding a property in the middle and passing it at the
end -- or the reverse -- is a compile error that nothing on a Windows machine
was able to see.

This is not a parser and does not try to be. It reads the stored properties of
each `struct` the project declares, in order, then finds calls that look like
`TypeName(label: ...)` and checks the labels are a subsequence of the declared
order and that every one of them exists. That is exactly the class of mistake
above and nothing more; anything it cannot read confidently, it skips.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# `let x`, `var x`, and the `@State private var x` forms, capturing the name.
PROPERTY = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:private|fileprivate|internal|public)?\s*"
    r"(?:static\s+)?(let|var)\s+([A-Za-z_]\w*)\s*(?::|=)"
)
STRUCT = re.compile(r"^(?:public\s+|internal\s+)?struct\s+([A-Z]\w*)")
# A computed property or a function body -- not part of the initialiser.
COMPUTED = re.compile(r"^\s*(?:@\w+\s+)*(?:private\s+|static\s+)*(?:var|func)\s+\w+[^=]*\{\s*$")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*", "", line) for line in text.split("\n"))


def swift_files():
    for base, _, names in os.walk(os.path.join(ROOT, "Arch")):
        for name in sorted(names):
            if name.endswith(".swift"):
                yield os.path.join(base, name)


def stored_properties(body):
    """The memberwise initialiser's parameters, in order.

    Anything with an explicit initialiser is still a parameter -- it simply has
    a default -- so only computed properties and functions are skipped.
    """
    out, explicit_init = [], False
    depth = 0
    for line in body.split("\n"):
        if re.match(r"^\s*(?:private\s+|public\s+)?init\s*\(", line):
            explicit_init = True
        opens, closes = line.count("{"), line.count("}")
        if depth == 0:
            match = PROPERTY.match(line)
            if match and not COMPUTED.match(line):
                # `var x: T { ... }` on one line is computed, not stored.
                if not re.search(r":\s*[^=]*\{", line):
                    out.append(match.group(2))
        depth += opens - closes
        depth = max(depth, 0)
    return None if explicit_init else out


def collect():
    """Every project struct, to the properties of its memberwise initialiser."""
    shapes = {}
    for path in swift_files():
        with open(path, encoding="utf-8") as handle:
            text = strip_comments(handle.read())
        lines = text.split("\n")
        for index, line in enumerate(lines):
            match = STRUCT.match(line)
            if not match:
                continue
            depth, body, started = 0, [], False
            for rest in lines[index:]:
                depth += rest.count("{") - rest.count("}")
                if rest.count("{"):
                    started = True
                body.append(rest)
                if started and depth <= 0:
                    break
            properties = stored_properties("\n".join(body[1:]))
            if properties:
                shapes[match.group(1)] = properties
    return shapes


def call_labels(text, start):
    """The top-level argument labels of the call opening at `start`."""
    depth, labels, current, in_string = 0, [], "", False
    i = start
    while i < len(text):
        ch = text[i]
        if ch == '"' and text[i - 1] != "\\":
            in_string = not in_string
        if not in_string:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
                if depth == 0:
                    labels.append(current)
                    break
            elif ch == "," and depth == 1:
                labels.append(current)
                current = ""
                i += 1
                continue
        if depth == 1 and ch != "(":
            current += ch
        i += 1

    out = []
    for piece in labels:
        found = re.match(r"\s*([A-Za-z_]\w*)\s*:", piece)
        out.append(found.group(1) if found else None)
    return out


def main():
    shapes = collect()
    problems = []
    for path in swift_files():
        with open(path, encoding="utf-8") as handle:
            text = strip_comments(handle.read())
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        for match in re.finditer(r"\b([A-Z]\w*)\(", text):
            name = match.group(1)
            if name not in shapes:
                continue
            order = shapes[name]
            labels = [l for l in call_labels(text, match.end() - 1) if l]
            if not labels:
                continue
            unknown = [l for l in labels if l not in order]
            line = text[:match.start()].count("\n") + 1
            if unknown:
                # A trailing closure, a different overload, or a genuine typo --
                # reported, because it is cheap to look at and cheap to ignore.
                problems.append("%s:%d  %s(...) has no %s"
                                % (rel, line, name, ", ".join(unknown)))
                continue
            positions = [order.index(l) for l in labels]
            if positions != sorted(positions):
                for a, b in zip(labels, labels[1:]):
                    if order.index(a) > order.index(b):
                        problems.append(
                            "%s:%d  %s(...): '%s' must precede '%s'"
                            % (rel, line, name, b, a))
                        break

    print("=" * 66)
    print("argument order")
    print("=" * 66)
    print("  structs read       %d" % len(shapes))
    if not problems:
        print("\n  every call matches the order its type declares.\n")
        return 0
    print("\n  %d problem(s):" % len(problems))
    for problem in problems:
        print("    - %s" % problem)
    print("\n  A memberwise initialiser takes its arguments in declaration")
    print("  order. Move the argument, or move the property.\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
