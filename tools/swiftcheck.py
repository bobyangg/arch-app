# -*- coding: utf-8 -*-
"""Cross-reference the Swift, since nothing here can be compiled.

Not a type checker and not trying to be. It answers one question: **does every
name this code uses actually exist somewhere in the project?** That is the class of
mistake that comes from writing against a type from memory -- calling
`PromptLibrary.question(for:)` when the function is `question(matching:)`, or
constructing a type whose spelling drifted.

Anything not declared in this project is ignored, so there is no need for a list of
everything in the standard library and Foundation. That means it is quiet about
real errors involving Apple's types, and loud about ours, which is the right way
round: ours are the ones no compiler has ever looked at.

    python tools/swiftcheck.py            # check the whole project
    python tools/swiftcheck.py Arch/Backend
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "Arch")

DECL = re.compile(r"^\s*(?:public\s+|private\s+|fileprivate\s+|internal\s+)?"
                  r"(?:final\s+)?(struct|enum|class|actor|protocol)\s+(\w+)")
TYPEALIAS = re.compile(r"^\s*(?:private\s+)?typealias\s+(\w+)")
MEMBER = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private(?:\(set\))?\s+|"
                    r"fileprivate\s+|internal\s+)?(?:static\s+)?"
                    r"(?:func|var|let|case|init)\s*(\w*)")
EXTENSION = re.compile(r"^\s*extension\s+(\w+)")


def swift_files(path):
    for base, _, names in os.walk(path):
        for name in sorted(names):
            if name.endswith(".swift"):
                yield os.path.join(base, name)


def strip_comments_and_strings(text):
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    # Interpolation is code, but the surrounding literal is not; blanking whole
    # strings would hide real calls inside \(...), so only plain literals go.
    text = re.sub(r'"""(?:[^"]|"(?!""))*"""', '""', text, flags=re.S)
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    return text


def collect():
    """{type: set(members)} plus the set of all declared type names."""
    types = {}
    order = []
    for path in swift_files(SOURCE):
        with open(path, encoding="utf-8") as handle:
            lines = strip_comments_and_strings(handle.read()).split("\n")

        # A stack, because types nest. With a single `current`, the closing brace
        # of a nested `enum Failure` inside `enum Keychain` ended the enclosing
        # type too, and every member declared after it was silently lost.
        stack = []
        depth = 0
        for line in lines:
            decl = DECL.match(line)
            ext = EXTENSION.match(line)
            alias = TYPEALIAS.match(line)

            if alias:
                types.setdefault(alias.group(1), set())
            if decl or ext:
                name = decl.group(2) if decl else ext.group(1)
                types.setdefault(name, set())
                order.append(name)
                # A nested type is also a member of the type around it: the rest
                # of the app refers to it as `Attestation.Failure`, and without
                # this that reads as a missing member rather than a nested enum.
                if stack:
                    types[stack[-1][0]].add(name)
                stack.append((name, depth))
            elif stack:
                m = MEMBER.match(line)
                if m and m.group(1):
                    types[stack[-1][0]].add(m.group(1))
                    # `case a, b, c` on one line.
                    if line.strip().startswith("case "):
                        for name in re.findall(r"\b(\w+)\b",
                                               line.strip()[5:].split("(")[0]):
                            types[stack[-1][0]].add(name)

            depth += line.count("{") - line.count("}")
            while stack and depth <= stack[-1][1]:
                stack.pop()
    return types


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "Arch"
    target = os.path.join(ROOT, target)

    types = collect()
    known = set(types)

    # Members that exist on everything, or that come from protocol conformance the
    # project declares rather than writes out.
    UNIVERSAL = {
        "init", "self", "Type", "shared", "allCases", "rawValue", "id",
        "description", "hashValue", "count", "first", "last", "map", "filter",
        "isEmpty", "contains", "sorted", "compactMap", "flatMap", "reduce",
        "append", "remove", "removeAll", "insert", "joined", "prefix", "suffix",
        "min", "max", "keys", "values", "enumerated", "indices", "startIndex",
        "endIndex", "reversed", "split", "trimmingCharacters", "components",
        "uppercased", "lowercased", "hasPrefix", "hasSuffix", "replacingOccurrences",
        "firstIndex", "lastIndex", "dropFirst", "dropLast", "sorted", "shuffled",
        "randomElement", "value", "none", "some", "zero", "now", "current",
    }

    problems = []
    checked = 0
    for path in swift_files(target):
        with open(path, encoding="utf-8") as handle:
            text = strip_comments_and_strings(handle.read())
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")

        for line_no, line in enumerate(text.split("\n"), 1):
            # `KnownType.member` -- only for types this project declares.
            for owner, member in re.findall(r"\b([A-Z]\w+)\.(\w+)", line):
                if owner not in known:
                    continue
                if member in UNIVERSAL or member in types[owner]:
                    continue
                checked += 1
                problems.append("%s:%d  %s.%s does not exist"
                                % (rel, line_no, owner, member))

    print("=" * 66)
    print("swift cross-reference check")
    print("=" * 66)
    print("  project types      %d" % len(known))
    print("  members indexed    %d" % sum(len(v) for v in types.values()))
    print("  checked under      %s" % os.path.relpath(target, ROOT).replace(os.sep, "/"))
    print()

    if problems:
        print("  %d problem(s):" % len(problems))
        for p in problems:
            print("    - %s" % p)
        print()
        print("  A name here resolves to nothing. Either it is a typo, or it is a")
        print("  member of an Apple type that shares a name with one of ours.")
        return 1

    print("  every project name used resolves to a declaration.")
    print()
    print("  This is not a compiler. It says nothing about types, argument labels,")
    print("  optionality or control flow -- only that the names exist.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
