#!/usr/bin/env python3
"""PLAN 0.3 §6.3 lints (lead): L1–L14 with the ratchet, L15 control-table pairing, L16, L17.

Run by scripts/lint.sh (which passes LINT_MODE=check|write and LINT_STRICT=0|1). Comments are stripped before
matching (string literals are kept); counts are occurrences, not lines.
"""
import os
import re
import sys

RATCHET = "scripts/lint-legacy.tsv"
# Rows that never go away (PLAN 0.3 §6.3): the app's main menu, PIP's context menu, the custom drag canvas.
PERMANENT = {
    ("L6", "Sources/Snaptic/Core/AppDelegate.swift"),
    ("L6", "Sources/Snaptic/Displays/PIP/PIPWindow.swift"),
    ("L5", "Sources/Snaptic/Displays/UI/ArrangementCanvas.swift"),
}
RATCHETED = ["L1", "L2", "L4", "L5", "L6", "L7", "L9", "L10", "L12", "L13", "L14"]


def strip_comments(text):
    """Removes // and /* */ comments, keeps string literals (incl. multi-line and raw strings) intact."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if text.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif text.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    if text[i] == "\n":
                        out.append("\n")
                    i += 1
            continue
        if c == "#" or c == '"':
            j = i
            while j < n and text[j] == "#":
                j += 1
            if j < n and text[j] == '"':
                hashes = j - i
                triple = text.startswith('"""', j)
                quote = '"""' if triple else '"'
                close = quote + "#" * hashes
                k = j + len(quote)
                while k < n:
                    if hashes == 0 and text[k] == "\\":
                        k += 2
                        continue
                    if text.startswith(close, k):
                        k += len(close)
                        break
                    if not triple and text[k] == "\n":
                        break
                    k += 1
                out.append(text[i:k])
                i = k
                continue
        out.append(c)
        i += 1
    return "".join(out)


def swift_files(root):
    for dirpath, _, files in os.walk(root):
        for f in sorted(files):
            if f.endswith(".swift"):
                yield os.path.join(dirpath, f)


def load(path):
    return strip_comments(open(path, encoding="utf-8").read())


SOURCES = sorted(list(swift_files("Sources/Snaptic")) + list(swift_files("Sources/SnapticKit")))
APP = [p for p in SOURCES if p.startswith("Sources/Snaptic/")]
TEXT = {p: load(p) for p in SOURCES}


def count(pattern, text):
    return len(re.findall(pattern, text))


def under(path, *prefixes):
    return any(path.startswith("Sources/Snaptic/" + p) for p in prefixes)


def is_menu_file(path):
    return "Menu" in os.path.basename(path)


SETTINGS_VIEWS = ("Displays/UI/", "Awake/UI/", "SettingsUI/", "Switcher/SettingsView.swift", "Switcher/SwitcherPages.swift",
                  "Core/GeneralPages.swift", "Core/Onboarding.swift", "Core/SettingsWindowHost.swift",
                  "Core/MenuBarPage.swift", "Core/CustomizeMenuSheet.swift")


def ratcheted_counts():
    found = {}

    def add(rule, path, n):
        if n:
            found[(rule, path)] = found.get((rule, path), 0) + n

    assertion = "Sources/Snaptic/Awake/Core/AssertionManager.swift"
    simulator = "Sources/Snaptic/Awake/Sources/ActivitySimulator.swift"
    for p in SOURCES:
        t = TEXT[p]
        # L1 sleep assertions only in AssertionManager; SetProperty banned (the swap replaces it).
        if p != assertion:
            add("L1", p, count(r"IOPMAssertionCreate", t))
        if p not in (assertion, simulator):
            add("L1", p, count(r"IOPMAssertionRelease\b", t))
        add("L1", p, count(r"IOPMAssertionSetProperty", t))
        # L2 activity and events only in ActivitySimulator.
        if p != simulator:
            add("L2", p, count(r"IOPMAssertionDeclareUserActivity|\.post\(tap:|CGEvent\(mouseEventSource", t))
        else:
            add("L2", p, count(r"mouseType:\s*\.(?!mouseMoved\b)\w+", t))
        if under(p, "Awake/"):
            add("L2", p, count(r"keyboardEventSource|CGEvent\(keyboardEvent|CGEvent\(scrollWheelEvent", t))
        # L4 banned everywhere.
        add("L4", p, count(r'UNUserNotificationCenter|import\s+CoreWLAN|import\s+IOBluetooth|CLLocationManager|"pmset"|"sudo"', t))
        # L9 only AwakeLogEvent cases reach the .awake category (through EventLog's overload).
        if p != "Sources/Snaptic/Core/EventLog.swift":
            add("L9", p, count(r"record\(\s*\.awake|EventCategory\.awake", t))
    for p in APP:
        t = TEXT[p]
        # L5 raw sliders, steppers and caption captions only in SettingsUI.
        if not under(p, "SettingsUI/"):
            add("L5", p, count(r"(?<![A-Za-z])Slider\(|(?<![A-Za-z])Stepper\(|\.font\(\.caption\)", t))
        # L6 NSMenuItem( only in the MenuKit files.
        if p not in ("Sources/Snaptic/Core/MenuKit.swift", "Sources/Snaptic/Core/MenuSliderRow.swift",
                     "Sources/Snaptic/Core/MenuSwitchHeader.swift"):
            add("L6", p, count(r"NSMenuItem\(", t))
        # L7 no manual change pokes in pages; no State(initialValue:) copies in Settings views.
        if under(p, "Displays/UI/", "Awake/UI/", "SettingsUI/"):
            add("L7", p, count(r"objectWillChange\.send\(\)", t))
        if under(p, *SETTINGS_VIEWS):
            add("L7", p, count(r"State\(initialValue:", t))
        # L10 Awake observers on main; no singletons or passUnretained in Awake.
        if under(p, "Awake/"):
            add("L10", p, count(r"queue:\s*nil|addObserver\(self,\s*selector:|static let shared|passUnretained\(self\)", t))
            lines = t.split("\n")
            for i, line in enumerate(lines):
                for _ in re.finditer(r"\.publisher\(for:", line):
                    statement = line
                    j = i + 1
                    while j < len(lines) and lines[j].strip().startswith("."):
                        statement += lines[j]
                        j += 1
                    if ".receive(on: DispatchQueue.main)" not in statement:
                        add("L10", p, 1)
        # L12 the regular control size only in the page header.
        if p != "Sources/Snaptic/SettingsUI/SettingsPageHeader.swift":
            add("L12", p, count(r"\.controlSize\(\.regular\)", t))
        # L13 no SwiftUI hosting in menus.
        base = os.path.basename(p)
        if ((under(p, "Core/") and (base.startswith("Menu") or base == "StatusMenu.swift"))
                or (under(p, "Displays/UI/") and "Menu" in base)
                or p in ("Sources/Snaptic/Awake/UI/AwakeMenuRows.swift", "Sources/Snaptic/Awake/UI/IndicatorController.swift")):
            add("L13", p, count(r"NSHostingView", t))
        # L14 .common run-loop modes in menus and Awake.
        if under(p, "Awake/") or is_menu_file(p):
            add("L14", p, count(r"scheduledTimer\(|RunLoop\.main\.perform(?!\(inModes:)|receive\(on:\s*RunLoop\.main|"
                                r"scheduler:\s*RunLoop\.main", t))
    return found


def unratcheted_problems():
    problems = []
    # L16 the activity gate is assigned only by SessionController; the CLI client never half-closes.
    for p in APP:
        t = TEXT[p]
        if p != "Sources/Snaptic/Awake/Core/SessionController.swift":
            for m in re.finditer(r"activityGate\s*=(?!=)|AwakeActivityGate\(", t):
                problems.append(f"{p}: L16 {m.group(0)!r} is only allowed in Awake/Core/SessionController.swift")
        if p == "Sources/Snaptic/Core/CLIClient.swift" and re.search(r"\bshutdown\(", t):
            problems.append(f"{p}: L16 shutdown( is banned (the client never half-closes)")
    # L17 duplicate keys never trap in Awake.
    for p in SOURCES:
        base = os.path.basename(p)
        awake = (p.startswith("Sources/Snaptic/Awake/") or (p.startswith("Sources/SnapticKit/") and base.startswith("Awake"))
                 or (p.startswith("Sources/SnapticKit/Config/") and base.startswith("ConfigAwake")))
        if awake and "uniqueKeysWithValues" in TEXT[p]:
            problems.append(f"{p}: L17 uniqueKeysWithValues is banned in Awake (use uniquingKeysWith: {{ first, _ in first }})")
    problems += l15()
    return problems


def l15():
    problems = []
    controls_dir = "Sources/SnapticKit/Controls"
    tables = {}
    for f in sorted(os.listdir(controls_dir)) if os.path.isdir(controls_dir) else []:
        if not f.endswith(".swift"):
            continue
        path = os.path.join(controls_dir, f)
        text = TEXT.get(path) or load(path)
        for m in re.finditer(r"\benum\s+(\w+)\s*:\s*ControlTable\b", text):
            name = m.group(1)
            if f != name + ".swift":
                problems.append(f"{path}: L15 table {name} must live in Controls/{name}.swift")
            ids = re.findall(r'ControlSpec\(\s*"([^"\\]*)"', text)
            bad = re.findall(r'ControlSpec\((?!\s*")', text)
            if bad:
                problems.append(f"{path}: L15 a ControlSpec id must be one plain string literal")
            tables[name] = ids
    registry = TEXT.get(os.path.join(controls_dir, "ControlRegistry.swift"), "")
    for name in tables:
        if not re.search(r"\b" + re.escape(name) + r"\.self\b", registry):
            problems.append(f"{controls_dir}/{name}.swift: L15 {name} is not listed in ControlRegistry.tables")
    used = {}
    for p in APP:
        t = TEXT[p]
        exempt = p.startswith("Sources/Snaptic/SettingsUI/") or p == "Sources/Snaptic/Core/MenuKit.swift"
        for m in re.finditer(r"\bControlID\(", t):
            rest = t[m.end():]
            if not re.match(r'\s*"[^"\\]*"\s*\)', rest) and not exempt:
                problems.append(f"{p}: L15 ControlID( takes one string literal")
        literals = re.findall(r'\bControlID\(\s*"([^"\\]*)"\s*\)', t)
        aliases = set(re.findall(r"typealias\s+Controls\s*=\s*(\w+)", t))
        if len(aliases) > 1:
            problems.append(f"{p}: L15 several typealias Controls name different tables: {sorted(aliases)}")
        if literals and not aliases:
            problems.append(f"{p}: L15 uses ControlID literals but declares no `typealias Controls = …`")
        for table in aliases:
            if table not in tables:
                problems.append(f"{p}: L15 typealias Controls = {table}: no such table in {controls_dir}")
                continue
            for lit in literals:
                if lit not in tables[table]:
                    problems.append(f"{p}: L15 ControlID(\"{lit}\") is not in {table}")
                used.setdefault(table, set()).add(lit)
    for table, ids in tables.items():
        for i in ids:
            if i not in used.get(table, set()):
                problems.append(f"{controls_dir}/{table}.swift: L15 {i} is declared but no view or builder uses it")
    return problems


def read_ratchet():
    rows = {}
    if not os.path.exists(RATCHET):
        return rows
    for line in open(RATCHET, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        rule, path, n, kind = line.split("\t")
        rows[(rule, path)] = (int(n), kind)
    return rows


def write_ratchet(found):
    keys = sorted(set(found) | PERMANENT, key=lambda k: (k[1], int(k[0][1:])))
    with open(RATCHET, "w", encoding="utf-8") as out:
        out.write("# rule\tpath\tcount\tpermanent|step (PLAN 0.3 §6.3). Counts are occurrences. Generated by\n")
        out.write("# scripts/lint.sh --write-ratchet; teams may lower or delete rows for paths they own (TEAMS.md).\n")
        for key in keys:
            n = found.get(key, 0)
            if n == 0 and key not in PERMANENT:
                continue
            kind = "permanent" if key in PERMANENT else "step"
            out.write(f"{key[0]}\t{key[1]}\t{n}\t{kind}\n")
    print(f"lint: wrote {RATCHET}")


def main():
    mode = os.environ.get("LINT_MODE", "check")
    strict = os.environ.get("LINT_STRICT", "0") == "1"
    found = ratcheted_counts()
    bad = 0
    if mode == "write":
        write_ratchet(found)
    else:
        rows = read_ratchet()
        for (rule, path), n in sorted(found.items(), key=lambda kv: (kv[0][1], kv[0][0])):
            allowed = rows.get((rule, path), (0, ""))[0]
            if n > allowed:
                print(f"lint: {path}: {rule} {n} occurrence(s), ratchet allows {allowed} (scripts/lint-legacy.tsv)",
                      file=sys.stderr)
                bad = 1
        for (rule, path), (n, kind) in sorted(rows.items()):
            if rule not in RATCHETED:
                print(f"lint: {RATCHET}: unknown rule {rule}", file=sys.stderr)
                bad = 1
                continue
            actual = found.get((rule, path), 0)
            if actual < n and kind != "permanent":
                message = f"{path}: {rule} is down to {actual} (ratchet row says {n}); lower or delete the row"
                if strict:
                    print("lint: " + message, file=sys.stderr)
                    bad = 1
                else:
                    print("lint warning: " + message, file=sys.stderr)
    for problem in unratcheted_problems():
        print("lint: " + problem, file=sys.stderr)
        bad = 1
    return bad


if __name__ == "__main__":
    sys.exit(main())
