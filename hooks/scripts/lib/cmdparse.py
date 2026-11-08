#!/usr/bin/env python3
"""Shell-command analysis shared by the guard and protect-config hooks.

The hooks receive the PreToolUse JSON on stdin. This module tokenises the Bash command into
segments (heredoc bodies dropped, quoted text kept as plain words), tracks the effective
directory through `cd`, looks one or more levels into `$( )`, backticks, `( )` and
`bash -c '...'`, and then decides what each real command does.

CLI:  cmdparse.py guard    -> prints the deny JSON (or nothing) for git commit/push on protected branches
      cmdparse.py protect  -> prints four lines: tool, session id, verdict (deny|write|ok), file_path

Standard library only. An internal error means "allow" for protect-config; guard fails closed only
when the raw text mentions `git ... commit|push`.

Known limits (by design, kept simple): paths or refs that only exist at run time (a variable set
outside the command, `$(...)` output, a file or stdin read by xargs / `python script.py`) are not
analysed; `echo <path> | xargs rm` is therefore not caught, only literal arguments are. Code in
`python -c` / `perl -e` is scanned for a delete verb next to a literal protected path, or for a
literal `git commit|push`. `find` with -delete / -exec rm refuses any start directory that is or
contains protected material, whatever the filters say. A `git checkout|switch` is followed only when
its target is a protected name or a branch that exists.
"""
import fnmatch
import glob as globmod
import json
import os
import re
import subprocess
import sys

PROTECTED_BRANCHES = ("master", "main", "develop")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PLACEHOLDER = "\x00"
MAX_DEPTH = 4

# Entries of the Claude config dir that are protected (besides projects/*/memory).
CONFIG_PROTECTED = (
    "commands", "rules", "agents", "skills", "hooks", "CLAUDE.md", "settings.json",
    "settings.local.json", ".claude-kit-manifest",
    ".claude-kit-layers", "protected-paths", "plugins",
)

# Top-level folders of the kit that may never be deleted or moved as a whole. Single files inside
# are ordinary, git-recoverable edits; `.git` and the layer folders (each its own repository) are
# protected at any depth.
KIT_TOP = ("commands", "rules", "agents", "skills", "hooks", "layers", "templates", "scripts", "tests")

SKIPWORDS = {"{", "!", "then", "do", "else", "elif", "if", "while", "until", "time"}
WRAPPERS = {"env", "sudo", "command", "nice", "exec", "nohup", "rtk", "builtin", "ionice",
            "timeout", "setsid", "xargs"}
WRAPPER_VALUE_OPTS = {
    "sudo": {"-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"},
    "env": {"-u", "-C", "-S"},
    "nice": {"-n"},
    "ionice": {"-c", "-n", "-p"},
    "timeout": {"-s", "-k"},
    "xargs": {"-I", "-L", "-n", "-P", "-s", "-d", "-E", "-a", "--max-args", "--max-procs",
              "--delimiter", "--arg-file", "--replace", "--max-lines", "--max-chars", "--eof"},
}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
VALUE_OPTS = {"shred": {"-n", "-s", "--iterations", "--size"}, "truncate": {"-s", "-r", "-o", "--size",
              "--reference"}}


# --------------------------------------------------------------------------- tokenising

class Seg:
    """One simple command: its words, redirection targets and nested command texts."""
    __slots__ = ("words", "redirs", "subs", "heres")

    def __init__(self):
        self.words = []
        self.redirs = []
        self.subs = []
        self.heres = []     # here-strings and heredoc bodies (only analysed when fed to a shell)

    def empty(self):
        return not (self.words or self.redirs or self.subs)


def find_close(t, i):
    """Index of the ')' matching an already-consumed '(' (len(t) when unbalanced)."""
    depth, n = 1, len(t)
    while i < n:
        c = t[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = t.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if c == '"':
            j = i + 1
            while j < n and t[j] != '"':
                j += 2 if t[j] == "\\" else 1
            i = j + 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def find_backtick(t, i):
    n = len(t)
    while i < n:
        if t[i] == "\\":
            i += 2
            continue
        if t[i] == "`":
            return i
        i += 1
    return n


def parse(text):
    """Split a shell command into Seg objects. Never raises on malformed input."""
    segs = []
    cur = Seg()
    buf = []
    st = {"inword": False, "mode": None}
    heredocs = []
    n = len(text)
    i = 0

    def flush():
        if not st["inword"]:
            return
        w = "".join(buf)
        buf.clear()
        st["inword"] = False
        mode = st["mode"]
        st["mode"] = None
        if mode == "out":
            cur.redirs.append(w)
        elif mode == "here":
            cur.heres.append(w)
        elif mode == "skip":
            pass
        else:
            cur.words.append(w)

    def end_seg():
        nonlocal cur
        flush()
        if not cur.empty():
            segs.append(cur)
        cur = Seg()

    def add_sub(inner):
        cur.subs.append(inner)
        buf.append(PLACEHOLDER)
        st["inword"] = True

    while i < n:
        c = text[i]
        if c == "\\":
            if i + 1 < n:
                if text[i + 1] != "\n":
                    buf.append(text[i + 1])
                    st["inword"] = True
                i += 2
            else:
                i += 1
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                j = n
            buf.append(text[i + 1:j])
            st["inword"] = True
            i = j + 1
            continue
        if c == '"':
            st["inword"] = True
            i += 1
            while i < n and text[i] != '"':
                d = text[i]
                if d == "\\" and i + 1 < n:
                    if text[i + 1] in '"\\$`':
                        buf.append(text[i + 1])
                    elif text[i + 1] != "\n":
                        buf.append(d + text[i + 1])
                    i += 2
                elif d == "$" and text.startswith("$(", i):
                    j = find_close(text, i + 2)
                    if not text.startswith("$((", i):
                        cur.subs.append(text[i + 2:j])
                    buf.append(PLACEHOLDER)
                    i = j + 1
                elif d == "`":
                    j = find_backtick(text, i + 1)
                    cur.subs.append(text[i + 1:j])
                    buf.append(PLACEHOLDER)
                    i = j + 1
                else:
                    buf.append(d)
                    i += 1
            i += 1
            continue
        if c == "$" and text.startswith("$(", i):
            j = find_close(text, i + 2)
            if text.startswith("$((", i):
                buf.append(PLACEHOLDER)
                st["inword"] = True
            else:
                add_sub(text[i + 2:j])
            i = j + 1
            continue
        if c == "$" and text.startswith("${", i):
            j = text.find("}", i)
            j = n - 1 if j < 0 else j
            buf.append(text[i:j + 1])
            st["inword"] = True
            i = j + 1
            continue
        if c == "`":
            j = find_backtick(text, i + 1)
            add_sub(text[i + 1:j])
            i = j + 1
            continue
        if c in " \t\r":
            flush()
            i += 1
            continue
        if c == "#" and not st["inword"]:
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "\n":
            end_seg()
            i += 1
            owner = segs[-1] if (heredocs and segs) else None
            for delim, dash in heredocs:
                body = []
                while i < n:
                    j = text.find("\n", i)
                    line = text[i:] if j < 0 else text[i:j]
                    i = n if j < 0 else j + 1
                    if (line.lstrip("\t") if dash else line) == delim:
                        break
                    body.append(line)
                if owner is not None:
                    owner.heres.append("\n".join(body))
            heredocs = []
            continue
        if c == ";":
            end_seg()
            i += 1
            continue
        if c == "&":
            if text.startswith("&>", i):
                flush()
                i += 3 if text.startswith("&>>", i) else 2
                st["mode"] = "out"
                continue
            end_seg()
            i += 2 if text.startswith("&&", i) else 1
            continue
        if c == "|":
            end_seg()
            i += 2 if text[i + 1:i + 2] in ("|", "&") else 1
            continue
        if c == "(":
            end_seg()
            j = find_close(text, i + 1)
            g = Seg()
            g.subs.append(text[i + 1:j])
            segs.append(g)
            i = j + 1
            continue
        if c == ")":
            end_seg()
            i += 1
            continue
        if c in "<>":
            if st["inword"] and "".join(buf).isdigit():
                buf.clear()
                st["inword"] = False
            else:
                flush()
            if text.startswith("<<<", i):
                st["mode"] = "here"
                i += 3
            elif text.startswith("<<", i):
                i += 2
                dash = text.startswith("-", i)
                if dash:
                    i += 1
                while i < n and text[i] in " \t":
                    i += 1
                delim = []
                while i < n and text[i] not in " \t\n;&|<>()":
                    if text[i] in "'\"\\":
                        i += 1
                        continue
                    delim.append(text[i])
                    i += 1
                heredocs.append(("".join(delim), dash))
            elif text.startswith("<(", i) or text.startswith(">(", i):
                j = find_close(text, i + 2)
                add_sub(text[i + 2:j])
                i = j + 1
            elif text.startswith(">&", i) or text.startswith("<&", i):
                skip = c == "<"
                i += 2
                k = i
                while k < n and (text[k].isdigit() or text[k] == "-"):
                    k += 1
                if k > i:
                    i = k
                else:
                    st["mode"] = "skip" if skip else "out"
            elif c == ">":
                i += 1
                if text[i:i + 1] in (">", "|"):
                    i += 1
                st["mode"] = "out"
            else:
                i += 1
                st["mode"] = "skip"
            continue
        buf.append(c)
        st["inword"] = True
        i += 1
    end_seg()
    return segs


def fallback_segments(text):
    """Conservative split used only if the tokenizer raised: first words of segments."""
    out = []
    for part in re.split(r"[;&|\n]+", text):
        part = part.strip().lstrip("({")
        if part:
            seg = Seg()
            seg.words = part.split()
            out.append(seg)
    return out


# --------------------------------------------------------------------------- environment

def home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def expand_str(word, variables):
    """Expand ~, $HOME, ${HOME} and known variables. None when it cannot be resolved."""
    if PLACEHOLDER in word:
        return None
    if word == "~" or word.startswith("~/"):
        word = home() + word[1:]
    elif word.startswith("~"):
        ex = os.path.expanduser(word)
        if ex == word:
            return None
        word = ex

    bad = []

    def sub(m):
        name = m.group(1) or m.group(2)
        if name in variables:
            return variables[name]
        if name == "HOME":
            return home()
        if name == "CLAUDE_CONFIG_DIR" and os.environ.get(name):
            return os.environ[name]
        bad.append(name)
        return ""

    word = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", sub, word)
    if bad or "$" in word:
        return None
    return word


def resolve(word, base, variables):
    """Absolute normalised path of `word` relative to `base`, or None."""
    s = expand_str(word, variables)
    if s is None or s == "":
        return None
    if not os.path.isabs(s):
        if not base:
            return None
        s = os.path.join(base, s)
    return os.path.normpath(s)


def command_of(words):
    """(command word, args, leading assignments) of a segment; command is None if absent."""
    i, n = 0, len(words)
    assigns = {}
    while i < n:
        w = words[i]
        m = ASSIGN.match(w)
        if m:
            k, _, v = w.partition("=")
            assigns[k] = v
            i += 1
            continue
        b = os.path.basename(w)
        if b in SKIPWORDS:
            i += 1
            continue
        if b in WRAPPERS:
            if b == "command" and any(x in ("-v", "-V") for x in words[i + 1:i + 3]):
                return None, [], assigns
            i += 1
            vals = WRAPPER_VALUE_OPTS.get(b, set())
            while i < n and (words[i].startswith("-") or (b == "env" and ASSIGN.match(words[i]))):
                if b == "env" and ASSIGN.match(words[i]):
                    k, _, v = words[i].partition("=")
                    assigns[k] = v
                i += 2 if words[i] in vals else 1
            if b == "timeout" and i < n:
                i += 1
            continue
        break
    if i >= n:
        return None, [], assigns
    return words[i], words[i + 1:], assigns


GIT_ENV = ("GIT_DIR", "GIT_WORK_TREE")
FIND_EXEC = ("-exec", "-execdir", "-ok", "-okdir")
PY_FLAG = re.compile(r"^-[A-Za-z]*c$")
PERL_FLAG = re.compile(r"^-[A-Za-z]*[eE]$")
DETACHED = "(detached)"


def normalise(cmd, args):
    """Map `busybox rm` and `gio trash` onto the plain delete verbs."""
    base = os.path.basename(cmd)
    if base == "busybox" and args:
        return args[0], args[1:]
    if base == "gio" and args and args[0] in ("trash", "remove"):
        return "trash", args[1:]
    return cmd, args


def ref_exists(repo, extra, name):
    """True when `name` is a protected branch name or a local/remote-tracking branch of the repo."""
    if name in PROTECTED_BRANCHES:
        return True
    for ref in ("refs/heads/" + name, "refs/remotes/origin/" + name):
        try:
            r = subprocess.run(["git"] + extra + ["rev-parse", "--verify", "--quiet", ref], cwd=repo,
                               capture_output=True, text=True, timeout=5)
            if r.returncode == 0:
                return True
        except Exception:
            return False
    return False


def switch_target(sub, rest, repo, extra):
    """Branch HEAD points to after `git checkout|switch rest`; None when it does not change."""
    pos = []
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--":
            return None if sub == "checkout" else (pos[0] if pos and ref_exists(repo, extra, pos[0]) else None)
        if a in ("-b", "-B", "-c", "-C", "--orphan", "--create", "--force-create") and i + 1 < len(rest):
            return rest[i + 1]
        if a in ("--detach", "-d"):
            return DETACHED
        if not a.startswith("-"):
            pos.append(a)
        i += 1
    if not pos or (sub == "checkout" and len(pos) != 1):
        return None
    return pos[0] if ref_exists(repo, extra, pos[0]) else None


def process(parsed, words, heres, cwd, variables, depth, events, branches, unk):
    """Emit the events of one simple command (and of the commands nested inside its arguments)."""
    cmd, args, assigns = parsed
    cmd, args = normalise(cmd, args)
    base = os.path.basename(cmd)
    ctx = {"branches": dict(branches), "unk": unk, "assigns": assigns}
    if depth < MAX_DEPTH:
        if base in SHELLS:
            for idx, a in enumerate(args):
                if re.match(r"^-[a-z]*c[a-z]*$", a) and idx + 1 < len(args):
                    walk(args[idx + 1], cwd, dict(variables), depth + 1, events, branches, unk)
                    break
            for h in heres:
                walk(h, cwd, dict(variables), depth + 1, events, branches, unk)
        elif base == "eval":
            walk(" ".join(args), cwd, dict(variables), depth + 1, events, branches, unk)
        elif base.startswith("python") or base == "perl":
            flag = PERL_FLAG if base == "perl" else PY_FLAG
            for idx, a in enumerate(args):
                if flag.match(a) and idx + 1 < len(args):
                    events.append(("pystr", args[idx + 1], cwd, dict(variables), ctx))
        elif base == "find":
            i = 0
            while i < len(args):
                if args[i] in FIND_EXEC:
                    j = i + 1
                    inner = []
                    while j < len(args) and args[j] not in (";", "+"):
                        inner.append(args[j])
                        j += 1
                    inner_parsed = command_of(inner) if inner else (None, [], {})
                    if inner_parsed[0] is not None:
                        process(inner_parsed, inner, [], cwd, variables, depth + 1, events, branches, unk)
                    i = j
                i += 1
    events.append(("cmd", cmd, args, cwd, dict(variables), words, ctx))
    if base == "git":
        sub, rest, repo, extra = parse_git(args, cwd, variables)
        if sub in ("checkout", "switch") and repo:
            target = switch_target(sub, rest, repo, extra)
            if target:
                branches[repo] = target


def walk(text, cwd, variables, depth, events, branches=None, unk=False):
    """Collect ('cmd', command, args, cwd, vars, words, ctx), ('redir', target, cwd, vars) and
    ('pystr', code, cwd, vars, ctx) events. `branches` maps a repo dir to the branch a
    `git checkout|switch` earlier in the same command line leaves it on."""
    if branches is None:
        branches = {}
    try:
        segs = parse(text)
    except Exception:
        segs = fallback_segments(text)
    for seg in segs:
        if depth < MAX_DEPTH:
            for sub in seg.subs:
                walk(sub, cwd, dict(variables), depth + 1, events, branches, unk)
        for r in seg.redirs:
            events.append(("redir", r, cwd, dict(variables)))
        if not seg.words:
            continue
        parsed = command_of(seg.words)
        cmd, args, assigns = parsed
        if cmd is None:
            for k, v in assigns.items():
                s = expand_str(v, variables)
                if s is not None:
                    variables[k] = s
            continue
        base = os.path.basename(cmd)
        if base in ("cd", "pushd"):
            target = next((a for a in args if not a.startswith("-")), None)
            new = None if target == "-" else (resolve(target, cwd, variables) if target else home())
            if new:
                cwd = new
                unk = False
            else:
                unk = True
            continue
        if base == "export":
            for a in args:
                if ASSIGN.match(a):
                    k, _, v = a.partition("=")
                    s = expand_str(v, variables)
                    if s is not None:
                        variables[k] = s
            continue
        process(parsed, seg.words, seg.heres, cwd, variables, depth, events, branches, unk)
    return cwd


def collect(command, cwd):
    events = []
    walk(command, cwd or os.getcwd(), {}, 0, events)
    return events


# --------------------------------------------------------------------------- git helpers

def parse_git(args, cwd, variables):
    """(subcommand, rest, repo dir or None, extra git options for rev-parse style calls)."""
    repo = cwd
    extra = []
    i, n = 0, len(args)
    while i < n:
        a = args[i]
        if a == "-C" and i + 1 < n:
            repo = resolve(args[i + 1], repo, variables) if repo else None
            i += 2
        elif a in ("-c", "--namespace", "--exec-path", "--super-prefix") and i + 1 < n:
            i += 2
        elif a in ("--git-dir", "--work-tree") and i + 1 < n:
            p = resolve(args[i + 1], repo, variables)
            if p:
                extra.append("%s=%s" % (a, p))
            i += 2
        elif a.startswith(("--git-dir=", "--work-tree=")):
            k, _, v = a.partition("=")
            p = resolve(v, repo, variables)
            if p:
                extra.append("%s=%s" % (k, p))
            i += 1
        elif a.startswith("-"):
            i += 1
        else:
            break
    sub = args[i] if i < n else None
    return sub, args[i + 1:], repo, extra


def current_branch(repo, extra):
    if not repo or not os.path.isdir(repo):
        return ""
    try:
        r = subprocess.run(["git"] + extra + ["symbolic-ref", "--short", "-q", "HEAD"], cwd=repo,
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def push_parts(rest):
    """(options, positionals) of the arguments after `git push`."""
    opts, pos = [], []
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--":
            pos.extend(rest[i + 1:])
            break
        if a in ("--repo", "-o", "--push-option", "--receive-pack", "--exec") and i + 1 < len(rest):
            opts.append(a)
            i += 2
            continue
        if a.startswith("-"):
            opts.append(a)
        else:
            pos.append(a)
        i += 1
    return opts, pos


def refspec_dest(r):
    r = r.lstrip("+")
    dest = r.rsplit(":", 1)[-1] if ":" in r else r
    if dest.startswith("refs/heads/"):
        dest = dest[len("refs/heads/"):]
    return dest


def deny_json(reason):
    return json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                              "permissionDecision": "deny",
                                              "permissionDecisionReason": reason}})


FORCE_MSG = ("Force-push blocked by the kit guard hook. Push normally, or rebase and open a new "
             "branch (--force-with-lease is allowed).")


def upstream_short(repo, extra, branch):
    """Short branch name of the configured upstream of `branch` ('' when none)."""
    if not repo or not os.path.isdir(repo):
        return ""
    ref = (branch + "@{u}") if branch else "@{u}"
    try:
        r = subprocess.run(["git"] + extra + ["rev-parse", "--abbrev-ref", ref], cwd=repo,
                           capture_output=True, text=True, timeout=5)
    except Exception:
        return ""
    out = r.stdout.strip() if r.returncode == 0 else ""
    return out.split("/", 1)[1] if "/" in out else ""


def kit_root():
    """Root of the kit this script belongs to (tests may override it with CLAUDE_KIT_ROOT)."""
    env = os.environ.get("CLAUDE_KIT_ROOT")
    if env:
        return env
    here = os.path.realpath(__file__)
    for _ in range(4):
        here = os.path.dirname(here)
    return here


def allow_remote_patterns():
    """Remote URL patterns whose repositories may take commits and pushes on protected branches.

    One pattern per line (fnmatch syntax, `#` starts a comment), read from `guard-allow-remotes` in the
    Claude config dir and in every layer in use. With no such file nothing is allowed, which is the
    default. Force pushes and --mirror/--all stay refused for these repositories too.
    """
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home(), ".claude")
    files = [os.path.join(cfg, "guard-allow-remotes")]
    try:
        with open(os.path.join(cfg, ".claude-kit-layers"), encoding="utf-8") as fh:
            for name in fh.read().split():
                if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name):
                    files.append(os.path.join(kit_root(), "layers", name, "guard-allow-remotes"))
    except OSError:
        pass
    out = []
    for path in files:
        try:
            with open(path, encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError:
            continue
        for line in lines:
            line = line.split("#", 1)[0].strip()
            if line:
                out.append(line)
    return out


def remote_allowed(repo, extra, remote):
    """True when `remote` of `repo` (a remote name or a URL) matches an allow pattern."""
    patterns = allow_remote_patterns()
    if not patterns or not repo or not os.path.isdir(repo):
        return False
    if re.search(r"[:/@]", remote):                       # `git push <url> ...`
        url = remote
    else:
        try:
            r = subprocess.run(["git"] + extra + ["remote", "get-url", remote], cwd=repo,
                               capture_output=True, text=True, timeout=5)
        except Exception:
            return False
        url = r.stdout.strip() if r.returncode == 0 else ""
    if not url:
        return False
    return any(fnmatch.fnmatchcase(c, pat) for pat in patterns for c in (url, re.sub(r"\.git$", "", url)))


def git_env_extra(repo, variables, assigns):
    """--git-dir / --work-tree options equivalent to GIT_DIR / GIT_WORK_TREE in force for a command."""
    out = []
    for k, opt in (("GIT_DIR", "--git-dir"), ("GIT_WORK_TREE", "--work-tree")):
        v = expand_str(assigns[k], variables) if k in assigns else variables.get(k)
        p = resolve(v, repo, variables) if v else None
        if p:
            out.append("%s=%s" % (opt, p))
    return out


MIRROR_MSG = ("Refusing to run '%s': --mirror and --all push every branch, protected ones included. "
              "Push the feature/*, bugfix/* or hotfix/* branch by name.")
PY_GIT = re.compile(r"\bgit\b[\"',\s\[\]]*(?:-[\w=-]+[\"',\s]*)*\b(commit|push)\b")


def judge(sub, rest, repo, extra, ecwd, variables, ctx, root, shown):
    """Reason to deny one `git commit|push`, or None."""
    # repo unresolved (`git -C "$X"`, `cd "$X"`): fall back to the repository of the session directory
    unresolved = repo is None or (ctx["unk"] and repo == ecwd)
    lookup = root if unresolved else repo
    refspecs = []
    opts = []
    pos = []
    if sub == "push":
        opts, pos = push_parts(rest)
        refspecs = [expand_str(r, variables) or r for r in pos[1:]]
        if any(o in ("--mirror", "--all", "--branches") for o in opts):
            return MIRROR_MSG % shown
        if any(o in ("-f", "--force") or re.match(r"^-[A-Za-z]*f[A-Za-z]*$", o) for o in opts) \
                or any(r.startswith("+") for r in refspecs):
            return FORCE_MSG
    git_extra = [] if unresolved else extra
    # Repositories whose remote is on the allow list may take commits and pushes on protected branches.
    if remote_allowed(lookup, git_extra, (pos[0] if sub == "push" and pos else "origin")):
        return None
    branch = ctx["branches"].get(lookup)
    if branch is None:
        branch = current_branch(lookup, git_extra)
    if branch in PROTECTED_BRANCHES:
        return ("Refusing to run '%s' on protected branch '%s'. Create a feature/*, bugfix/* "
                "or hotfix/* branch first (the repo convention), then commit there."
                % (shown, branch))
    if sub == "push":
        for r in refspecs:
            if refspec_dest(r) in PROTECTED_BRANCHES:
                return ("Refusing to run '%s': it pushes to protected branch '%s'. Push a "
                        "feature/*, bugfix/* or hotfix/* branch and open a pull request."
                        % (shown, refspec_dest(r)))
        if not refspecs and "--tags" not in opts:
            up = upstream_short(lookup, git_extra, branch)
            if up in PROTECTED_BRANCHES and up != branch:
                return ("Refusing to run '%s': branch '%s' tracks protected branch '%s', so a plain "
                        "push would update it. Push explicitly: git push -u origin HEAD."
                        % (shown, branch, up))
    return None


# Self-repair commands of third-party tools. They rewrite the configuration shared with the dev
# containers (settings.json, ~/.claude.json) with host-only absolute paths, or append broken entries to
# it, and the damage shows up much later and somewhere else.
SELF_REPAIR_VERBS = {"tokensave": {"doctor", "install", "reinstall", "upgrade"}}
SELF_REPAIR_MSG = ("Blocked by the kit guard hook: `{what}` rewrites the Claude Code configuration shared "
                   "with the dev containers (hooks and MCP servers get host-only absolute paths), which "
                   "breaks the tool inside the containers. Do not run it. If it is really needed, take a "
                   "snapshot (scripts/backup-config.sh) and ask the user to run it themselves with `! <command>`.")
SELF_REPAIR_ANYWHERE = re.compile(r"\btokensave\b.*\b(doctor|install|reinstall|upgrade)\b"
                                  r"|\brtk\b.*\binit\b.*(\s-[A-Za-z]*g\b|--global)", re.S)


def self_repair_reason(cmd, args, words=()):
    """Deny reason when the command is a third-party tool's self-repair, else None. `words` are the
    original words of the segment: the parser treats rtk as a transparent wrapper, so `rtk init -g`
    reaches `cmd` as plain `init`."""
    for i, w in enumerate(words):
        if os.path.basename(w) == "rtk":
            rest = list(words[i + 1:])
            if rest and rest[0] == "proxy":
                rest = rest[1:]
            if rest and rest[0] == "init" and any(a == "--global" or re.match(r"^-[A-Za-z]*g[A-Za-z]*$", a)
                                                  for a in rest[1:]):
                return SELF_REPAIR_MSG.format(what="rtk init -g")
            if rest and os.path.basename(rest[0]) in SELF_REPAIR_VERBS:
                return self_repair_reason(rest[0], rest[1:])
            break
    base = os.path.basename(cmd)
    verbs = SELF_REPAIR_VERBS.get(base)
    if verbs:
        sub = next((a for a in args if not a.startswith("-")), None)
        if sub in verbs:
            return SELF_REPAIR_MSG.format(what=base + " " + sub)
    return None


def guard(command, cwd):
    """Reason to deny, or None."""
    root = cwd or os.getcwd()
    if os.environ.get("CMDPARSE_TEST_RAISE"):          # test hook: simulates a parser crash
        raise RuntimeError("forced")
    for ev in collect(command, root):
        if ev[0] == "cmd":
            r = self_repair_reason(ev[1], ev[2], ev[5])
            if r:
                return r
        if ev[0] == "pystr":
            m = PY_GIT.search(ev[1])
            if m:
                r = judge(m.group(1), [], ev[2], [], ev[2], ev[3], ev[4], root,
                          "git " + m.group(1) + " (inside a script string)")
                if r:
                    return r
            continue
        if ev[0] != "cmd" or os.path.basename(ev[1]) != "git":
            continue
        _, _, args, ecwd, variables, words, ctx = ev
        sub, rest, repo, extra = parse_git(args, ecwd, variables)
        if sub not in ("commit", "push"):
            continue
        if repo is not None and not any(e.startswith("--git-dir") for e in extra):
            extra = extra + git_env_extra(repo, variables, ctx["assigns"])
        r = judge(sub, rest, repo, extra, ecwd, variables, ctx, root, " ".join(words)[:60])
        if r:
            return r
    return None


# --------------------------------------------------------------------------- protect-config

def inside(p, root):
    return p == root or root == "/" or p.startswith(root.rstrip("/") + "/")


def variants(p):
    out = {os.path.normpath(p)}
    try:
        out.add(os.path.realpath(p))
    except Exception:
        pass
    return out


class Roots:
    def __init__(self, kit):
        h = home()
        cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(h, ".claude")
        self.config = variants(cfg)
        self.kit = variants(kit) if kit else set()
        self.extra = self._extra_roots(h, cfg, kit)

    @staticmethod
    def _extra_roots(h, cfg, kit):
        """Extra protected folders: `protected-paths` in the config dir and in every layer in use.

        One path per line, `~` allowed, `#` starts a comment. This is how a layer protects its own
        data (a notes folder, say) without the core knowing about it.
        """
        files = [os.path.join(cfg, "protected-paths")]
        try:
            with open(os.path.join(cfg, ".claude-kit-layers"), encoding="utf-8") as fh:
                for name in fh.read().split():
                    if kit and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name):
                        files.append(os.path.join(kit, "layers", name, "protected-paths"))
        except OSError:
            pass
        out = set()
        for path in files:
            try:
                with open(path, encoding="utf-8") as fh:
                    lines = fh.read().splitlines()
            except OSError:
                continue
            for line in lines:
                line = line.split("#", 1)[0].strip()
                if not line:
                    continue
                if line == "~" or line.startswith("~/"):
                    line = h + line[1:]
                if os.path.isabs(line):
                    out |= variants(line)
        return out

    def config_rel_protected(self, rel):
        """rel = components below the config dir."""
        if not rel or not rel[0]:
            return False
        if rel[0] in CONFIG_PROTECTED:
            return True
        if rel[0] == "projects":
            return len(rel) < 3 or rel[2] == "memory"
        return False

    @staticmethod
    def kit_protected(v, r, ancestors):
        """True when deleting or moving `v` would remove the kit, a top-level folder, a layer or .git."""
        if ancestors and inside(r, v):
            return True
        if not inside(v, r):
            return False
        rel = [c for c in v[len(r):].strip("/").split("/") if c]
        if not rel or rel[0] == ".git":
            return True
        if len(rel) == 1 and rel[0] in KIT_TOP:
            return True
        return rel[0] == "layers" and len(rel) <= 2

    @staticmethod
    def folder_protected(v, r, ancestors, contents=False):
        """A folder from a protected-paths file: the folder, its ancestors and any `.git` inside it
        are protected; single files and subfolders inside it are ordinary edits.
        `contents` means v stands for "everything directly inside v" (a trailing wildcard)."""
        if ancestors and inside(r, v) and v != r:
            return True
        if v == r:
            return not contents
        if not inside(v, r):
            return False
        return ".git" in [c for c in v[len(r):].split("/") if c]

    def deny_path(self, p, ancestors=True, contents=False):
        """True when deleting or moving `p` would remove protected material."""
        for v in variants(p):
            for r in self.kit:
                if self.kit_protected(v, r, ancestors):
                    return True
            for r in self.extra:
                if self.folder_protected(v, r, ancestors, contents):
                    return True
            for c in self.config:
                if v == c or (ancestors and inside(c, v)):
                    return True
                if inside(v, c) and self.config_rel_protected(v[len(c):].strip("/").split("/")):
                    return True
        return False

    def write_path(self, p):
        """True when `p` lies inside the kit or the protected part of the config dir."""
        for v in variants(p):
            for r in self.kit:
                if inside(v, r):
                    return True
            for c in self.config:
                if inside(v, c) and v != c and self.config_rel_protected(v[len(c):].strip("/").split("/")):
                    return True
        return False

    def path_protected(self, p):
        """True when editing the file `p` touches the kit or the protected part of a config dir
        (the configured one, or any `.claude` directory, e.g. the other side of a bind mount)."""
        if self.write_path(p):
            return True
        parts = [c for c in p.split("/") if c]
        return any(c == ".claude" and i + 1 < len(parts) and self.config_rel_protected(parts[i + 1:])
                   for i, c in enumerate(parts))

    def deny_glob(self, w):
        """Deny decision for an absolute path containing wildcard characters."""
        first = min(i for i, ch in enumerate(w) if ch in "*?[")
        prefix = w[:first]
        if prefix.endswith("/"):
            if self.deny_path(prefix.rstrip("/") or "/", ancestors=False, contents=True):
                return True
        else:
            d = os.path.dirname(prefix) or "/"
            comp = w[len(d.rstrip("/")) + 1:].split("/", 1)[0]
            names = [os.path.basename(r) for r in self.kit | self.extra if os.path.dirname(r) in variants(d)]
            if variants(d) & self.config:
                names += list(CONFIG_PROTECTED) + ["projects"]
            elif variants(d) & {os.path.dirname(c) for c in self.config}:
                names += [os.path.basename(c) for c in self.config]
            if any(fnmatch.fnmatch(nm, comp) for nm in names):
                return True
        try:
            for hit in globmod.glob(w)[:2000]:
                if self.deny_path(hit):
                    return True
        except Exception:
            pass
        return False

    def deny_arg(self, word, cwd, variables):
        s = expand_str(word, variables)
        if s is None or s == "":
            return False
        if not os.path.isabs(s):
            if not cwd:
                return False
            s = os.path.join(cwd, s)
        s = os.path.normpath(s)
        if re.search(r"[*?\[]", s):
            return self.deny_glob(s)
        return self.deny_path(s)


def positional(args, value_opts=()):
    out = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            out.extend(args[i + 1:])
            break
        if a in value_opts:
            i += 2
            continue
        if a.startswith("-") and len(a) > 1:
            i += 1
            continue
        out.append(a)
        i += 1
    return out


def mv_sources(args):
    """Source operands of mv / git mv."""
    target_dir = any(a in ("-t", "--target-directory") or a.startswith("--target-directory=") for a in args)
    pos = positional(args, ("-t", "--target-directory", "-S", "--suffix"))
    if target_dir or len(pos) <= 1:
        return pos
    return pos[:-1]


def mv_dest(args):
    pos = positional(args, ("-t", "--target-directory", "-S", "--suffix"))
    for i, a in enumerate(args):
        if a in ("-t", "--target-directory") and i + 1 < len(args):
            return args[i + 1]
        if a.startswith("--target-directory="):
            return a.split("=", 1)[1]
    return pos[-1] if len(pos) > 1 else None


DELETERS = {"rm", "rmdir", "unlink", "shred", "truncate", "trash", "trash-put"}
EXEC_DELETERS = {"rm", "rmdir", "unlink", "shred", "mv", "trash", "trash-put"}
RSYNC_VALUE_OPTS = ("-e", "--rsh", "--exclude", "--include", "--exclude-from", "--include-from",
                    "-f", "--filter", "--files-from", "--backup-dir", "--partial-dir", "--log-file",
                    "--temp-dir", "-T", "--compare-dest", "--copy-dest", "--link-dest", "--port",
                    "--rsync-path", "--bwlimit", "--max-size", "--min-size", "--timeout")
CODE_DELETE = re.compile(r"\b(rm|rmtree|rmdir|unlink|remove|removedirs|rename|move|replace)\b")
CODE_PATH = re.compile(r"(?:~|\$HOME|\$\{HOME\}|/)[^\s'\",;)\]}]*")


def scan_code(roots, code, cwd, variables):
    """Conservative look into `python -c` / `perl -e` code: a delete verb together with a literal
    protected path. Paths built at run time are a known limit."""
    if not CODE_DELETE.search(code):
        return False
    return any(roots.deny_arg(m.group(0), cwd, variables) for m in CODE_PATH.finditer(code))
WRITERS_ALL = {"tee", "chmod", "chown", "touch", "patch"}
WRITERS_DEST = {"cp", "install", "ln", "mv", "rsync"}
GIT_WRITES = {"commit", "checkout", "switch", "reset", "stash", "merge", "rebase", "pull"}


def protect(command, cwd, kit):
    """Return 'deny', 'write' or 'ok' for a Bash command."""
    roots = Roots(kit)
    events = collect(command, cwd)
    wrote = False
    for ev in events:
        if ev[0] == "redir":
            _, target, ecwd, variables = ev
            p = resolve(target, ecwd, variables)
            if p and roots.write_path(p):
                wrote = True
            continue
        if ev[0] == "pystr":
            if scan_code(roots, ev[1], ev[2], ev[3]):
                return "deny"
            continue
        _, cmd, args, ecwd, variables, _w = ev[:6]
        base = os.path.basename(cmd)
        if base in DELETERS:
            for w in positional(args, VALUE_OPTS.get(base, ())):
                if roots.deny_arg(w, ecwd, variables):
                    return "deny"
        elif base == "mv":
            for w in mv_sources(args):
                if roots.deny_arg(w, ecwd, variables):
                    return "deny"
        elif base == "find":
            starts = []
            for a in args:
                if a.startswith("-") or a in ("(", "!", ")"):
                    break
                starts.append(a)
            deleting = "-delete" in args
            for i, a in enumerate(args):
                if a in FIND_EXEC and i + 1 < len(args) \
                        and normalise(args[i + 1], args[i + 2:])[0] in EXEC_DELETERS:
                    deleting = True
            if deleting:
                # a start directory that is, or contains, protected material is refused whatever the
                # filters say (they are not evaluated)
                for w in starts or ["."]:
                    s = resolve(w, ecwd, variables)
                    if s and roots.deny_path(s, ancestors=True):
                        return "deny"
        elif base == "rsync":
            if any(a in ("--delete", "--del", "--remove-source-files") or a.startswith("--delete-")
                   for a in args):
                ops = positional(args, RSYNC_VALUE_OPTS)
                dests = ops[-1:]
                if "--remove-source-files" in args:
                    dests = ops
                for w in dests:
                    if roots.deny_arg(w, ecwd, variables):
                        return "deny"
        elif base == "git":
            sub, rest, repo, extra = parse_git(args, ecwd, variables)
            if sub in ("rm", "mv"):
                paths = mv_sources(rest) if sub == "mv" else positional(rest, ())
                for w in paths:
                    if roots.deny_arg(w, repo, variables):
                        return "deny"
            elif sub == "clean":
                if not any(a in ("-n", "--dry-run") or re.match(r"^-[a-z]*n[a-z]*$", a) for a in rest) \
                        and repo and any(inside(v, r) for v in variants(repo) for r in roots.kit | roots.extra):
                    return "deny"
            if sub in GIT_WRITES and repo and roots.write_path(os.path.join(repo, "x")):
                wrote = True
        # non-blocking: does the command write to the configuration or the kit?
        if base in WRITERS_ALL:
            targets = positional(args)
        elif base in WRITERS_DEST:
            d = mv_dest(args)
            targets = [d] if d else []
        elif base in ("sed", "perl") and any(a == "--in-place" or re.match(r"^-[A-Za-z]*i", a) for a in args):
            targets = positional(args)
        elif base.startswith("python"):
            targets = [a for a in args if not a.startswith("-")]
        elif base == "install.sh" or (base in SHELLS and args and os.path.basename(args[0]) == "install.sh"):
            targets = [cmd if base == "install.sh" else args[0]]
        else:
            targets = []
        for w in targets:
            p = resolve(w, ecwd, variables)
            if p and roots.write_path(p):
                wrote = True
    return "write" if wrote else "ok"


# --------------------------------------------------------------------------- CLI

def main(argv):
    mode = argv[1] if len(argv) > 1 else ""
    try:
        data = json.load(sys.stdin)
        ti = data.get("tool_input") or {}
        if not isinstance(ti, dict):
            ti = {}
        tool = data.get("tool_name", "") or ""
        cwd = data.get("cwd") or os.getcwd()
        if mode == "guard":
            cmd = ti.get("command") or ""
            if cmd:
                try:
                    reason = guard(cmd, cwd)
                except Exception:
                    # fail closed for the guard: a command that mentions a commit or push and cannot be
                    # analysed is refused rather than waved through
                    reason = None
                    if re.search(r"\bgit\b.*\b(commit|push)\b", cmd, re.S):
                        reason = ("Could not parse the command, so the protected-branch check could not "
                                  "run. Run git commit/push without chaining, or ask the user.")
                    elif SELF_REPAIR_ANYWHERE.search(cmd):
                        reason = ("Could not parse the command, so the check for tool self-repair "
                                  "(tokensave doctor/install/reinstall/upgrade, rtk init -g) could not run. "
                                  "Do not run those; ask the user.")
                if reason:
                    print(deny_json(reason))
        elif mode == "protect":
            kit = os.environ.get("CLAUDE_KIT_ROOT") or ""
            verdict, fpath = "ok", ""
            if tool == "Bash":
                cmd = ti.get("command") or ""
                if cmd:
                    verdict = protect(cmd, cwd, kit)
            else:
                fpath = (ti.get("file_path") or "").replace("\n", " ")
                verdict = "ok"
                if fpath:
                    full = os.path.normpath(fpath if os.path.isabs(fpath) else os.path.join(cwd, fpath))
                    if Roots(os.environ.get("CLAUDE_KIT_ROOT") or "").path_protected(full):
                        verdict = "path"
            print(tool)
            print(data.get("session_id", "") or "nosession")
            print(verdict)
            print(fpath)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
