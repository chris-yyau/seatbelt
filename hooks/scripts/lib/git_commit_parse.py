# Shared git-commit command parsing for seatbelt hooks.
# Single source of truth so detect-commit / commitlint / signing agree on
# what counts as a git commit — including option-prefixed invocations
# (git -c/-C/--git-dir ... commit), a command/builtin wrapper, a
# backslash-escaped git, and leading KEY=VALUE env assignments.
import re
import shlex

# git global options (appearing BEFORE the subcommand) that consume the
# following token as their argument. Inline --opt=value forms need no
# entry here — they are a single token and skipped generically.
_ARG_OPTS = {
    "-C", "-c", "--exec-path", "--git-dir", "--work-tree",
    "--namespace", "--super-prefix", "--config-env", "--attr-source",
}


def _split_segments(cmd):
    """Split a command line into segments on UNQUOTED shell control
    operators (; | & and newline), honoring single/double quotes and
    backslash escapes. Splitting on the raw string — before shlex strips
    quotes — is what keeps an operator inside a quoted argument (e.g. a
    commit message "fix: a | b") from being mistaken for a real separator.
    Redirection operators that embed & or | (>&, 2>&1, &>, >|) are NOT
    separators. This covers the common shell forms; it is not a full shell
    grammar (process substitution / subshell grouping are not modelled)."""
    segments, buf = [], []
    quote = None
    i, n = 0, len(cmd)
    while i < n:
        ch = cmd[i]
        if quote is not None:
            buf.append(ch)
            if ch == "\\" and quote == '"' and i + 1 < n:
                buf.append(cmd[i + 1]); i += 2; continue
            if ch == quote:
                quote = None
            i += 1; continue
        if ch in ("'", '"'):
            quote = ch; buf.append(ch); i += 1; continue
        if ch == "\\" and i + 1 < n:
            buf.append(ch); buf.append(cmd[i + 1]); i += 2; continue
        if ch in "&|;\n":
            prev = cmd[i - 1] if i > 0 else ""
            nxt = cmd[i + 1] if i + 1 < n else ""
            # redirection operators (>&, <&, 2>&1, &>, &>>, >|) embed & or |
            # but are not command separators
            if ch == "&" and (prev in "<>" or nxt == ">"):
                buf.append(ch); i += 1; continue
            if ch == "|" and prev == ">":
                buf.append(ch); i += 1; continue
            segments.append("".join(buf)); buf = []
            i += 1
            while i < n and cmd[i] in "&|;":  # collapse &&, ||, ;; runs
                i += 1
            continue
        buf.append(ch); i += 1
    segments.append("".join(buf))
    return segments


def commit_args(cmd):
    """Return the token list following `git commit` for the first matching
    segment of a (possibly chained) shell command, or None if it is not a
    git commit. An empty list means `git commit` with no further arguments."""
    for seg in _split_segments(cmd):
        seg = seg.strip()
        if not seg:
            continue
        try:
            tokens = shlex.split(seg)  # posix: also resolves \\git -> git
        except ValueError:
            continue  # unbalanced quotes — an invalid command the shell rejects too
        # strip leading KEY=VALUE env assignments
        while tokens and re.match(r"^\w+=", tokens[0]):
            tokens = tokens[1:]
        # unwrap a command/builtin prefix. `-v`/`-V` mean *inspect*, not
        # execute (command -v git prints git's path), so those are NOT commits.
        if tokens and tokens[0] in ("command", "builtin"):
            tokens = tokens[1:]
            inspect = False
            while tokens and tokens[0].startswith("-") and tokens[0] != "--":
                if "v" in tokens[0].lower():
                    inspect = True
                tokens = tokens[1:]
            if tokens and tokens[0] == "--":
                tokens = tokens[1:]
            if inspect:
                continue
        if not tokens or tokens[0] != "git":
            continue
        # skip git global options to reach the subcommand
        i = 1
        while i < len(tokens):
            t = tokens[i]
            if not t.startswith("-"):
                break
            i += 2 if t in _ARG_OPTS else 1
        if i < len(tokens) and tokens[i] == "commit":
            return tokens[i + 1:]
    return None


if __name__ == "__main__":
    # Self-check: run `python3 git_commit_parse.py` — asserts, no output on failure.
    C = commit_args
    # option-prefixed / wrapped forms that must be DETECTED
    assert C("git commit -m x") == ["-m", "x"]
    assert C("git -c user.name=x commit -m x") == ["-m", "x"]
    assert C("git -C /tmp commit -m x") == ["-m", "x"]
    assert C("git --git-dir=/tmp/.git commit -S") == ["-S"]
    assert C("command git commit") == []
    assert C("command -p git commit") == []
    assert C("command -- git commit") == []
    assert C("\\git commit --amend") == ["--amend"]
    assert C("SKIP=1 git commit -m x") == ["-m", "x"]
    assert C("npm install && git commit -m x") == ["-m", "x"]
    # operators inside a quoted argument must NOT split the command
    assert C('git commit -m "fix: a | b"') == ["-m", "fix: a | b"]
    assert C('git commit -m "a; b && c"') == ["-m", "a; b && c"]
    assert C('git commit -m "&&" --no-gpg-sign') == ["-m", "&&", "--no-gpg-sign"]
    # redirection operators embed & / | but are not separators
    assert C('git commit 2>&1 -m "invalid message"') == ["2>&1", "-m", "invalid message"]
    assert C("git commit -m x &> log") == ["-m", "x", "&>", "log"]
    assert C("git commit -m x >| out") == ["-m", "x", ">|", "out"]
    # NON-commits that must be IGNORED
    assert C("git push") is None
    assert C("grep 'git commit' file") is None
    assert C("git status") is None
    assert C('echo "git commit" | cat') is None
    assert C("command -v git commit") is None   # inspection, not execution
    assert C("command -V git commit") is None
    print("git_commit_parse self-check ok")
