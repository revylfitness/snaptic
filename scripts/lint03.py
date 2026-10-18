#!/usr/bin/env python3
"""PLAN 0.3 §6.3 lints (lead): L1–L14 with the ratchet, L15 control-table pairing, L16, L17, and TEAMS rule 2
(closures run by the main queue, a main-queue observer, a timer or KVO wrap `MainActor.assumeIsolated`).

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
        if starts_string(text, i):
            k = string_end(text, i)
            out.append(text[i:k])
            i = k
            continue
        out.append(c)
        i += 1
    return "".join(out)


def starts_string(text, i):
    """Whether a string literal (`"`, `\"\"\"`, `#"`, `##"` …) starts at `text[i]`."""
    j = i
    while j < len(text) and text[j] == "#":
        j += 1
    return j < len(text) and text[j] == '"'


def string_end(text, i):
    """The index just past the string literal starting at `text[i]`. An interpolation (a backslash, the raw
    string's hashes, then a parenthesis) is skipped as code, so a quote inside it doesn't end the string."""
    n = len(text)
    j = i
    while j < n and text[j] == "#":
        j += 1
    hashes = j - i
    triple = text.startswith('"' * 3, j)
    quote = '"' * 3 if triple else '"'
    close = quote + "#" * hashes
    escape = "\\" + "#" * hashes
    k = j + len(quote)
    while k < n:
        if text.startswith(escape, k):
            k += len(escape)
            if k < n and text[k] == "(":
                k = code_end(text, k + 1)
            else:
                k += 1
            continue
        if text.startswith(close, k):
            return k + len(close)
        if not triple and text[k] == "\n":
            return k
        k += 1
    return n


def code_end(text, k):
    """The index just past the `)` that closes code starting at `text[k]` (strings and nested brackets skipped)."""
    n = len(text)
    depth = 0
    while k < n:
        c = text[k]
        if starts_string(text, k):
            k = string_end(text, k)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return k + 1
            depth -= 1
        k += 1
    return n


def matching_close(text, k):
    """`text[k]` is `(` or `{`: the index of the bracket that closes it (strings skipped), or -1."""
    end = code_end(text, k + 1)
    return end - 1 if end <= len(text) and text[end - 1:end] in (")", "}", "]") else -1


def self_check():
    """Pins the comment stripper on the cases a naive scan gets wrong (review code F6.7)."""
    bs, q = "\\", '"'
    cases = [
        # A quote inside an interpolation doesn't end the string; the comment after it is still removed.
        (f'let a = {q}{bs}(b ? {q}x{q} : {q}y{q}) // no{q} // c\nx', f'let a = {q}{bs}(b ? {q}x{q} : {q}y{q}) // no{q} \nx'),
        (f'f({q}{bs}(g({q}//{q})){q}) // c', f'f({q}{bs}(g({q}//{q})){q}) '),
        # Raw strings: a lone backslash is literal; backslash-hash-paren interpolates.
        (f'#{q}a {bs}({q}# // c', f'#{q}a {bs}({q}# '),
        (f'#{q}{bs}#(v ? {q}q{q} : {q}r{q}){q}# /* c */ y', f'#{q}{bs}#(v ? {q}q{q} : {q}r{q}){q}#  y'),
        (f'{q*3}\nline {q}quoted{q} // kept\n{q*3} // c', f'{q*3}\nline {q}quoted{q} // kept\n{q*3} '),
        (f'{q}esc {bs}{q} // still string{q} // c', f'{q}esc {bs}{q} // still string{q} '),
    ]
    problems = []
    for source, expected in cases:
        got = strip_comments(source)
        if got != expected:
            problems.append(f"self-check: strip_comments({source!r}) = {got!r}, expected {expected!r}")
    # Rule 2 (review5 code N4): True = must be reported.
    wrap = "MainActor.assumeIsolated { self?.g() }"
    rule2_cases = [
        (f"DispatchQueue.main\n    .asyncAfter(deadline: .now() + 1) {{ [weak self] in self?.g() }}", True),
        (f"DispatchQueue.main.asyncAfter(deadline: .now() + 1) {{ [weak self] in {wrap} }}", False),
        (f"DispatchQueue.main.asyncAfter(deadline: .now() + 1) {{ [weak self] in\n self?.n = 1\n {wrap}\n}}", True),
        (f"let q = DispatchQueue.main\nq.asyncAfter(deadline: .now() + 1) {{ [weak self] in self?.g() }}", True),
        (f"private let queue: DispatchQueue = .main\nfunc f() {{ self.queue.asyncAfter(deadline: .now()) {{ g() }} }}", True),
        (f"let queue = DispatchQueue(label: \"x\")\nqueue.asyncAfter(deadline: .now() + 1) {{ [weak self] in self?.g() }}",
         False),
        (f"let oq = OperationQueue.main\nc.addObserver(forName: .x, object: nil, queue: oq) {{ [weak self] _ in self?.g() }}",
         True),
        (f"c.addObserver(forName: .x, object: nil, queue: .main) {{ [weak self] note in\n"
         f" let v = note.object\n MainActor.assumeIsolated {{ self?.h(v) }}\n}}", False),
        (f"o = i.observe(\\.isVisible, options: [.new]) {{ [weak self] item, _ in\n let v = item.isVisible\n"
         f" DispatchQueue.main.async {{ MainActor.assumeIsolated {{ self?.h(v) }} }}\n}}", False),
        (f"DispatchQueue.main.asyncAfter(deadline: .now()) {{ [weak self] in\n guard let self else {{ return }}\n"
         f" MainActor.assumeIsolated {{ self.g() }}\n}}", False),
    ]
    for source, flagged in rule2_cases:
        if bool(rule2_file("Sources/Snaptic/SelfCheck.swift", source)) != flagged:
            problems.append(f"self-check: rule 2 {'missed' if flagged else 'wrongly reported'} {source!r}")
    return problems


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
            add("L9", p, count(r"record\(\s*\.awake\b|EventCategory\.awake\b", t))
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
            add("L10", p, count(r"queue:\s*nil|addObserver\(self,\s*selector:|passUnretained\(self\)|"
                                r"\b(?:static|class)\s+(?:let|var)\s+(?:shared|sharedInstance|instance)\b", t))
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
                                r"scheduler:\s*RunLoop\.main|forMode:\s*(?:\.default|RunLoop\.Mode\.default)\b|"
                                r"\bin:\s*(?:\.default|RunLoop\.Mode\.default)\b|\.defaultRunLoopMode\b", t))
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
    problems += rule2()
    problems += menu_contributors()
    problems += old_terms()
    return problems


# 0.2 names that UI strings (`L("…")`) no longer use (PLAN 0.3 §4.2 terms table; review5 ux N1), matched without
# case, with the 0.3 word to use. CLI verbs and config keys are not in `L()` prose and stay.
OLD_TERMS = {
    "smart hidpi": "Sharper text",
    "virtual screen": "virtual display",
    "match ui size": "Match Text Size",
    "menu-bar strip": "Black Menu Bar Background",
    "native-halved": "Half of Native Resolution",
    "on-screen display": "Brightness indicator",
    "recording screen": "recording display",
}
# Occurrences still waiting for their owner's fix in step-4 fix round 2 (D: Management, C: Brightness/Input; review5
# ux N1). A count may only go down: more fails, fewer prints a warning to lower or delete the entry (lead).
OLD_TERMS_PENDING = {
    ("Sources/Snaptic/Displays/Brightness/MenuBarOverlaysController.swift", "menu-bar strip"): 1,
    ("Sources/Snaptic/Displays/Input/OSDController.swift", "on-screen display"): 1,
    ("Sources/Snaptic/Displays/Management/ResolutionController.swift", "native-halved"): 1,
    ("Sources/Snaptic/Displays/Management/ResolutionController.swift", "match ui size"): 3,
    ("Sources/Snaptic/Displays/Management/SmartHiDPIController.swift", "smart hidpi"): 14,
    ("Sources/Snaptic/Displays/Management/VirtualController.swift", "virtual screen"): 8,
    ("Sources/Snaptic/Displays/Management/VirtualController.swift", "recording screen"): 1,
    ("Sources/Snaptic/Displays/Management/VirtualHostsService.swift", "virtual screen"): 4,
    ("Sources/Snaptic/Displays/Platform/DisplayRegistry.swift", "virtual screen"): 1,
}


def old_terms():
    found = {}
    for p in APP:
        for m in re.finditer(r'\bL\(\s*"((?:[^"\\\n]|\\.)*)"', TEXT[p]):
            text = m.group(1).lower()
            for term in OLD_TERMS:
                if term in text:
                    found[(p, term)] = found.get((p, term), 0) + text.count(term)
    problems = []
    for (p, term), n in sorted(found.items()):
        allowed = OLD_TERMS_PENDING.get((p, term), 0)
        if n > allowed:
            problems.append(f"{p}: UI text says the 0.2 name “{term}” {n} time(s) (allowed {allowed}); "
                            f"use “{OLD_TERMS[term]}” (PLAN 0.3 §4.2)")
    for (p, term), n in sorted(OLD_TERMS_PENDING.items()):
        if found.get((p, term), 0) < n:
            print(f"lint warning: {p}: “{term}” is down to {found.get((p, term), 0)}; lower OLD_TERMS_PENDING "
                  f"({n}) in scripts/lint03.py", file=sys.stderr)
    return problems


def menu_contributors():
    """Every `DisplayMenuContributor` conformer is in `DisplaysModule.menuContributorTypes`, the list
    `--selftest-controls` checks against the frozen 0.2 menu ids (R5-13)."""
    module = "Sources/Snaptic/Displays/DisplaysModule.swift"
    listed = re.search(r"static let menuContributorTypes[^=]*=\s*\[([^\]]*)\]", TEXT.get(module, ""))
    if not listed:
        return [f"{module}: menuContributorTypes not found"]
    names = set(re.findall(r"(\w+)\.self", listed.group(1)))
    problems = []
    for p in APP:
        for m in re.finditer(r"\b(?:class|struct|enum|extension)\s+(\w+)[^{]*?:[^{]*\bDisplayMenuContributor\b", TEXT[p]):
            if m.group(1) not in names:
                problems.append(f"{p}: {m.group(1)} conforms to DisplayMenuContributor but isn't listed in "
                                "DisplaysModule.menuContributorTypes")
    return problems


# TEAMS rule 2: these calls run their closure on the main thread but not on the main actor (the closure is
# @Sendable), so its body wraps `MainActor.assumeIsolated`. `asyncAfter` counts only on the main queue (also with
# the call on the next line, and through a name the same file binds to `.main`) and observers only with
# `queue: .main` (or such a name); a `DispatchWorkItem` passed as `execute:` is looked up in the same file. Outside
# its `assumeIsolated` blocks the closure may read its own parameters but not `self` (a partial wrap), apart from
# the capture list and `guard let self` / `if let self`.
# Known limits: a main-actor member used without `self.` outside the wrap (Swift 5.8 implicit self after
# `guard let self`), a queue passed in from another file, and Combine `publisher(for:)` sinks (L10 checks those in
# Awake, for `receive(on:)` only) are not seen.
RULE2_CALL = re.compile(r"\.asyncAfter\(|\baddObserver\(\s*forName:|(?<![\w.])Timer\(|\bscheduledTimer\(|\.observe\(\s*\\")
RULE2_TOP = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private|final)\s+)*"
                       r"(?:class|struct|enum|extension|actor)\s+([\w.]+)", re.M)
# Types whose observers deliberately touch no main-actor state (path, top-level type): reason.
RULE2_EXEMPT = {
    ("Sources/Snaptic/Switcher/WindowManager.swift", "FocusSession"):
        "@unchecked Sendable; its workspace observers only hop to the session's own AX thread",
}


def rule2_closure(t, m):
    """The closure the call at `m` runs (trailing, a labeled literal, or a `DispatchWorkItem` named by
    `execute:`), its argument text, or (None, args) when none is found."""
    po = t.index("(", m.start() + 1)
    pc = matching_close(t, po)
    if pc < 0:
        return None, ""
    args = t[po:pc + 1]

    def block(at):
        end = matching_close(t, at)
        return t[at:end + 1] if end >= 0 else None

    labeled = re.search(r"(?:execute|block|using|handler|changeHandler):\s*\{", args)
    if labeled:
        return block(po + labeled.end() - 1), args
    named = re.search(r"execute:\s*(\w+)\s*\)$", args)
    if named:
        defs = list(re.finditer(r"\b(?:let|var)\s+" + named.group(1) + r"\s*=\s*DispatchWorkItem\s*(?:\([^)]*\))?\s*\{",
                                t[:m.start()]))
        return (block(defs[-1].end() - 1) if defs else None), args
    trailing = re.match(r"\s*\{", t[pc + 1:])
    if trailing:
        return block(pc + 1 + trailing.end() - 1), args
    return None, args


def rule2():
    problems = []
    for p in APP:
        problems += rule2_file(p, TEXT[p])
    return problems


def rule2_file(p, t):
    problems = []
    tops = [(m.start(), m.group(1)) for m in RULE2_TOP.finditer(t)]
    for m in RULE2_CALL.finditer(t):
        call = m.group(0)
        if call == ".asyncAfter(" and not rule2_main_receiver(t, t[max(0, m.start() - 200):m.start()]):
            continue
        body, args = rule2_closure(t, m)
        if call.startswith("addObserver") and not rule2_main_observer_queue(t, args):
            continue
        if call.endswith("Timer(") and body is None and "selector:" in args:
            continue
        enclosing = next((name for at, name in reversed(tops) if at < m.start()), "")
        if (p, enclosing) in RULE2_EXEMPT:
            continue
        line = t.count("\n", 0, m.start()) + 1
        if body is None:
            problems.append(f"{p}:{line}: rule 2 can't find the closure {call.strip()} runs "
                            "(pass a literal or a local DispatchWorkItem)")
        elif "assumeIsolated" not in body:
            problems.append(f"{p}:{line}: rule 2 the closure {call.strip()} runs must wrap MainActor.assumeIsolated")
        elif rule2_outside_self(body):
            problems.append(f"{p}:{line}: rule 2 the closure {call.strip()} runs uses self outside its "
                            "MainActor.assumeIsolated block")
    return problems


# `.main`, `DispatchQueue.main` or `OperationQueue.main` (what rule 2's calls run on when they run on main).
RULE2_MAIN = r"(?:(?:DispatchQueue|OperationQueue)\s*)?\.main\b"


def rule2_bound_to_main(t, name):
    """True when the file binds `name` (a stored property or a local) to the main queue."""
    return re.search(r"(?:\b(?:let|var)\s+|\bself\.|(?<![\w.]))" + re.escape(name)
                     + r"\s*(?::\s*(?:DispatchQueue|OperationQueue)\??\s*)?=\s*" + RULE2_MAIN, t) is not None


def rule2_main_receiver(t, before):
    """`before` is the text just before `.asyncAfter(`: the receiver is the main queue, written out (possibly on
    the line above) or as a name the same file binds to it."""
    if re.search(r"(?:DispatchQueue\s*)?\.main\s*$", before):
        return True
    named = re.search(r"(?<![\w.])(?:self\??\.)?(\w+)\s*$", before)
    return bool(named) and named.group(1) not in ("main", "self") and rule2_bound_to_main(t, named.group(1))


def rule2_main_observer_queue(t, args):
    if re.search(r"queue:\s*" + RULE2_MAIN, args):
        return True
    named = re.search(r"queue:\s*(?:self\??\.)?(\w+)\b", args)
    return bool(named) and named.group(1) not in ("nil", "main") and rule2_bound_to_main(t, named.group(1))


def rule2_outside_self(body):
    """True when the closure body, with its `MainActor.assumeIsolated { … }` blocks, its capture list and any
    `guard let self` / `if let self` binding removed, still mentions `self`."""
    rest, i = "", 0
    for m in re.finditer(r"MainActor\.assumeIsolated\s*\{", body):
        if m.start() < i:
            continue
        end = matching_close(body, m.end() - 1)
        if end < 0:
            return False
        rest += body[i:m.start()]
        i = end + 1
    rest += body[i:]
    rest = re.sub(r"^\{\s*\[[^\]]*\]", "{", rest)
    rest = re.sub(r"\b(?:guard|if)\s+let\s+self\b(?:\s*=\s*self\b)?", "", rest)
    return re.search(r"(?<![\w.])self\b", rest) is not None


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
    for problem in self_check():
        print("lint: " + problem, file=sys.stderr)
        bad = 1
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
