#!/usr/bin/env bash
# Tests for hooks/scripts/guard.sh and hooks/scripts/protect-config.sh.
#
# Both hooks are run the way Claude Code runs them: the PreToolUse JSON goes to stdin. The JSON is
# built with python3 json.dumps from variables, so no command under test is ever executed or
# written as a literal command line. Everything happens in throw-away directories: git repos, a
# fake HOME, a fake Claude config dir, a fake kit and a fake notes folder. The real ~/.claude is never read.
#
# usage: tests/hooks.sh            (HOOKS_DIR overrides the scripts directory under test)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$repo_root/hooks/scripts}"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
export CLAUDE_KIT_ROOT="$T/kit"
export TMPDIR="$T/tmp"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
KIT="$CLAUDE_KIT_ROOT"
CFG="$CLAUDE_CONFIG_DIR"
EXTRA="$HOME/Notes"
mkdir -p "$HOME" "$TMPDIR" "$CFG/rules" "$CFG/cache" "$CFG/projects/X/memory" \
  "$KIT/rules" "$KIT/commands" "$KIT/scripts" "$KIT/layers/mine" "$EXTRA/inner"
: >"$CFG/CLAUDE.md"
: >"$KIT/commands/x.md"
# Extra protected folders come from protected-paths files: one in the config dir, one per layer in use.
printf '%s\n' '~/Notes   # a folder the user wants kept' >"$CFG/protected-paths"
printf 'mine\n' >"$CFG/.claude-kit-layers"
printf '%s\n' '/tmp/layer-protected-sample' >"$KIT/layers/mine/protected-paths"

git_init() { # dir branch
  mkdir -p "$1"
  git -C "$1" init -q -b "$2"
  git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
}
MASTER="$T/master-repo"
FEATURE="$T/feature-repo"
git_init "$MASTER" master
git_init "$FEATURE" feature/x
git -C "$KIT" init -q -b feature/kit
git -C "$MASTER" branch feature/z
# a feature branch that tracks develop (plain push would update it) and one that tracks itself
BARE="$T/bare.git"
git init -q --bare "$BARE"
UP="$T/up-repo"
git_init "$UP" feature/u
git -C "$UP" remote add origin "$BARE"
git -C "$UP" push -q origin feature/u:develop feature/u:feature/u
git -C "$UP" branch -q -u origin/develop
git -C "$UP" branch -q feature/own
git -C "$UP" branch -q -u origin/feature/u feature/own

# Consent: repositories whose remote matches a guard-allow-remotes pattern may use protected branches.
printf '%s\n' '# personal repositories' 'git@github.com:Me/allowed-*' >"$KIT/layers/mine/guard-allow-remotes"
printf '%s\n' 'https://example.invalid/team/shared.git' >"$CFG/guard-allow-remotes"
ALLOWED="$T/allowed-repo"
git_init "$ALLOWED" main
git -C "$ALLOWED" remote add origin git@github.com:Me/allowed-kit.git
ALLOWED2="$T/allowed-repo2"
git_init "$ALLOWED2" master
git -C "$ALLOWED2" remote add origin https://example.invalid/team/shared.git
OTHER="$T/other-remote-repo"
git_init "$OTHER" main
git -C "$OTHER" remote add origin git@github.com:Me/not-listed.git

pass=0
fail=0

payload() { # tool cwd session key value
  python3 -c 'import json,sys
t, cwd, sid, key, val = sys.argv[1:6]
print(json.dumps({"tool_name": t, "tool_input": {key: val}, "cwd": cwd, "session_id": sid,
                  "transcript_path": "/home/u/.claude/projects/p/s.jsonl"}))' "$@"
}

report() { # name expected actual
  if [ "$2" = "$3" ]; then
    printf 'PASS %-62s (%s)\n' "$1" "$3"
    pass=$((pass + 1))
  else
    printf 'FAIL %-62s expected %s, got %s\n' "$1" "$2" "$3"
    fail=$((fail + 1))
  fi
}

verdict_of() { # output exit-code
  if [ "$2" -ne 0 ]; then
    echo "exit$2"
    return
  fi
  case "$1" in
    *'"permissionDecision": "deny"'*) echo deny ;;
    *systemMessage*) echo reminder ;;
    "") echo allow ;;
    *) echo "odd:$1" ;;
  esac
}

# t_guard NAME EXPECT CWD COMMAND
t_guard() {
  local out rc=0
  out=$(payload Bash "$3" g1 command "$4" | bash "$HOOKS_DIR/guard.sh") || rc=$?
  report "guard: $1" "$2" "$(verdict_of "$out" "$rc")"
}

# t_prot NAME EXPECT CWD COMMAND   (Bash tool; a fresh session id each time)
t_prot() {
  local out rc=0
  out=$(payload Bash "$3" "p$RANDOM$RANDOM" command "$4" | bash "$HOOKS_DIR/protect-config.sh") || rc=$?
  report "protect: $1" "$2" "$(verdict_of "$out" "$rc")"
}

# t_file NAME EXPECT TOOL PATH [SESSION]
t_file() {
  local out rc=0
  out=$(payload "$3" "$T" "${5:-f$RANDOM$RANDOM}" file_path "$4" | bash "$HOOKS_DIR/protect-config.sh") || rc=$?
  report "protect: $1" "$2" "$(verdict_of "$out" "$rc")"
}

# ------------------------------------------------------------------ guard
t_guard "echo mentioning git commit" allow "$MASTER" "echo 'git commit later'"
t_guard "grep for git push" allow "$MASTER" "grep -n 'git push' README.md"
t_guard "plain git commit on master" deny "$MASTER" "git commit -m x"
t_guard "plain git commit on feature" allow "$FEATURE" "git commit -m x"
t_guard "plain git status on master" allow "$MASTER" "git status"
t_guard "cd feature && commit, from master cwd" allow "$MASTER" "cd $FEATURE && git commit -m x"
t_guard "cd master && commit, from feature cwd" deny "$FEATURE" "cd $MASTER && git commit -m x"
t_guard "git -C master commit, from feature" deny "$FEATURE" "git -C $MASTER commit -m x"
t_guard "git -C master push origin HEAD" deny "$FEATURE" "git -C $MASTER push origin HEAD"
t_guard "git -C feature commit, from master" allow "$MASTER" "git -C $FEATURE commit -m x"
t_guard "heredoc then commit on a later line" deny "$MASTER" $'cat > msg.txt <<EOF\nhello\nEOF\ngit commit -F msg.txt'
t_guard "commit text only inside a heredoc" allow "$MASTER" $'cat <<\'EOF\'\ngit commit -m x\nEOF'
t_guard "env assignment before commit" deny "$MASTER" "FOO=1 git commit -m x"
t_guard "env wrapper before commit" deny "$MASTER" "env FOO=1 git commit -m x"
t_guard "bash -c commit on master" deny "$MASTER" "bash -c 'git commit -m x'"
t_guard "bash -c commit on feature" allow "$FEATURE" "bash -c 'git commit -m x'"
t_guard "command substitution commit" deny "$MASTER" 'echo "$(git commit -m x)"'
t_guard "subshell commit" deny "$MASTER" "(git commit -m x)"
t_guard "pipeline then commit" deny "$MASTER" "git diff | cat; git commit -m x"
t_guard "git global option -c before commit" deny "$MASTER" "git -c user.name=a commit -m x"
t_guard "push --force-with-lease on feature" allow "$FEATURE" "git push --force-with-lease origin HEAD"
t_guard "push --force-if-includes on feature" allow "$FEATURE" "git push --force-with-lease --force-if-includes"
t_guard "push -f on feature" deny "$FEATURE" "git push -f"
t_guard "push --force on feature" deny "$FEATURE" "git push --force origin HEAD"
t_guard "push origin +x on feature" deny "$FEATURE" "git push origin +x"
t_guard "push origin HEAD:main from feature" deny "$FEATURE" "git push origin HEAD:main"
t_guard "push origin develop from feature" deny "$FEATURE" "git push origin develop"
t_guard "push origin x:refs/heads/main" deny "$FEATURE" "git push origin x:refs/heads/main"
t_guard "push -u origin HEAD on feature" allow "$FEATURE" "git push -u origin HEAD"
t_guard "push origin feature/y on feature" allow "$FEATURE" "git push origin feature/y"
t_guard "empty command" allow "$MASTER" ""
t_guard "unbalanced quote does not crash" allow "$FEATURE" "echo 'unterminated"

# --- branch changes inside one command line
t_guard "switch master; commit, from feature" deny "$FEATURE" "git switch master; git commit -m x"
t_guard "checkout master && commit, from feature" deny "$FEATURE" "git checkout master && git commit -m x"
t_guard "switch -c new && commit, from master" allow "$MASTER" "git switch -c feature/y && git commit -m x"
t_guard "checkout -b new && commit, from master" allow "$MASTER" "git checkout -b feature/y && git commit -m x"
t_guard "checkout -B new && commit, from master" allow "$MASTER" "git checkout -B feature/y && git commit -m x"
t_guard "checkout existing branch, from master" allow "$MASTER" "git checkout feature/z && git commit -m x"
t_guard "checkout master then new branch" allow "$FEATURE" "git checkout master && git switch -c feature/q && git commit -m x"
t_guard "checkout -- file stays on master" deny "$MASTER" "git checkout -- a.txt && git commit -m x"
t_guard "checkout <path> stays on master" deny "$MASTER" "git checkout a.txt && git commit -m x"
t_guard "checkout <path> stays on feature" allow "$FEATURE" "git checkout a.txt; git commit -m x"
t_guard "switch --detach is not protected" allow "$MASTER" "git switch --detach HEAD && git commit -m x"
t_guard "push after switch master" deny "$FEATURE" "git switch master && git push origin HEAD"
t_guard "-C repo switch then commit" allow "$MASTER" "git -C $MASTER switch -c feature/y && git -C $MASTER commit -m x"
t_guard "switch in master repo, commit in other" deny "$FEATURE" "git -C $FEATURE switch master && git -C $FEATURE commit -m x"

# --- push forms, variables, GIT_DIR
t_guard "push --mirror" deny "$FEATURE" "git push --mirror"
t_guard "push --all" deny "$FEATURE" "git push --all origin"
t_guard "push --tags" allow "$FEATURE" "git push --tags"
t_guard "push origin \$B (B=master)" deny "$FEATURE" 'B=master; git push origin $B'
t_guard "push origin \$B (export B=develop)" deny "$FEATURE" 'export B=develop; git push origin HEAD:$B'
t_guard "push origin \$B (B=feature/y)" allow "$FEATURE" 'B=feature/y; git push origin $B'
t_guard "push origin +\$B" deny "$FEATURE" 'B=feature/y; git push origin +$B'
t_guard "GIT_DIR of master repo, cwd /tmp" deny "$T" "cd /tmp && GIT_DIR=$MASTER/.git git commit -m x"
t_guard "GIT_DIR of feature repo, cwd master" allow "$MASTER" "GIT_DIR=$FEATURE/.git git commit -m x"
t_guard "export GIT_DIR of master repo" deny "$T" "export GIT_DIR=$MASTER/.git; cd /tmp; git commit -m x"
t_guard "env GIT_DIR of master repo" deny "$T" "env GIT_DIR=$MASTER/.git git commit -m x"
t_guard "plain push, branch tracks develop" deny "$UP" "git push"
t_guard "plain push to origin, tracks develop" deny "$UP" "git push origin"
t_guard "push --tags, branch tracks develop" allow "$UP" "git push --tags"
t_guard "push -u origin HEAD, tracks develop" allow "$UP" "git push -u origin HEAD"
t_guard "plain push, branch tracks itself" allow "$UP" "git switch feature/own && git push"
t_guard "plain push on a feature without upstream" allow "$FEATURE" "git push"

# --- unresolved repo, parser failure, xargs / find -exec / strings
t_guard "git -C \"\$PWD/..\" commit, cwd master" deny "$MASTER" 'git -C "$PWD/.." commit -m x'
t_guard "git -C \"\$PWD/..\" commit, cwd feature" allow "$FEATURE" 'git -C "$PWD/.." commit -m x'
t_guard "cd \"\$X\" && commit, cwd master" deny "$MASTER" 'cd "$NOPE" && git commit -m x'
t_guard "cd \"\$X\" && commit, cwd feature" allow "$FEATURE" 'cd "$NOPE" && git commit -m x'
t_guard "xargs git commit on master" deny "$MASTER" "echo x | xargs -n 1 git commit -m"
t_guard "find -exec git commit on master" deny "$MASTER" "find . -maxdepth 0 -exec git commit -m x {} +"
t_guard "find -exec git commit on feature" allow "$FEATURE" "find . -maxdepth 0 -exec git commit -m x {} +"
t_guard "sh <<< 'git commit' on master" deny "$MASTER" "sh <<< 'git commit -m x'"
t_guard "bash heredoc with git commit" deny "$MASTER" $'bash <<EOF\ngit commit -m x\nEOF'
t_guard "cat <<< 'git commit' is only text" allow "$MASTER" "cat <<< 'git commit -m x'"
t_guard "eval commit on master" deny "$MASTER" "eval 'git commit -m x'"
t_guard "python -c git commit on master" deny "$MASTER" "python3 -c 'import os; os.system(\"git commit -m x\")'"
t_guard "python -c git commit on feature" allow "$FEATURE" "python3 -c 'import os; os.system(\"git commit -m x\")'"
t_guard "python -c without git" allow "$MASTER" "python3 -c 'print(1)'"
t_guard_raise() { # parser crash (forced) on a command that mentions commit
  local out rc=0
  out=$(payload Bash "$FEATURE" g1 command "$2" | CMDPARSE_TEST_RAISE=1 bash "$HOOKS_DIR/guard.sh") || rc=$?
  report "guard: $1" "$3" "$(verdict_of "$out" "$rc")"
}
t_guard_raise "parser crash, git commit mentioned" "git commit -m x" deny
t_guard_raise "parser crash, unrelated command" "ls -la" allow
t_guard_raise "parser crash, tokensave doctor mentioned" "tokensave doctor" deny
t_guard_raise "parser crash, rtk init -g mentioned" "rtk init -g" deny

# ------------------------------------------------------------------ guard: tool self-repair
t_guard "tokensave doctor" deny "$FEATURE" "tokensave doctor"
t_guard "tokensave install" deny "$FEATURE" "tokensave install"
t_guard "tokensave reinstall" deny "$FEATURE" "tokensave reinstall"
t_guard "tokensave upgrade" deny "$FEATURE" "tokensave upgrade"
t_guard "tokensave doctor by absolute path" deny "$FEATURE" "/home/x/.local/bin/tokensave doctor"
t_guard "tokensave doctor with a flag first" deny "$FEATURE" "tokensave --verbose doctor"
t_guard "tokensave doctor after a cd and &&" deny "$FEATURE" "cd $MASTER && tokensave doctor"
t_guard "tokensave doctor in bash -c" deny "$FEATURE" "bash -c 'tokensave doctor'"
t_guard "tokensave doctor behind env" deny "$FEATURE" "env X=1 tokensave doctor"
t_guard "tokensave doctor behind rtk" deny "$FEATURE" "rtk tokensave doctor"
t_guard "tokensave doctor behind rtk proxy" deny "$FEATURE" "rtk proxy tokensave doctor"
t_guard "rtk init -g" deny "$FEATURE" "rtk init -g"
t_guard "rtk init --global" deny "$FEATURE" "rtk init --global"
t_guard "rtk init -g behind a wrapper" deny "$FEATURE" "sudo rtk init -g"
t_guard "tokensave status" allow "$FEATURE" "tokensave status"
t_guard "tokensave sync" allow "$FEATURE" "tokensave sync"
t_guard "tokensave init (per project)" allow "$FEATURE" "tokensave init"
t_guard "tokensave serve" allow "$FEATURE" "tokensave serve"
t_guard "tokensave --version" allow "$FEATURE" "tokensave --version"
t_guard "echo mentioning tokensave doctor" allow "$FEATURE" "echo 'run tokensave doctor later'"
t_guard "grep for tokensave doctor" allow "$FEATURE" "grep -rn 'tokensave doctor' README.md"
t_guard "rtk init (per project)" allow "$FEATURE" "rtk init"
t_guard "rtk gain" allow "$FEATURE" "rtk gain"
t_guard "rtk git status" allow "$FEATURE" "rtk git status"

# ------------------------------------------------------------------ protect-config (Bash)
t_prot "rm -rf /tmp/x" allow "$T" "rm -rf /tmp/x"
t_prot "echo mentioning rm -rf ~/.claude" allow "$T" "echo 'never rm -rf ~/.claude'"
t_prot "cd kit && rm -rf /tmp/build" allow "$T" "cd $KIT && rm -rf /tmp/build"
# A single file inside the kit is a git-recoverable edit; whole folders, layers and .git are not.
t_prot "cd kit && git mv a b" allow "$T" "cd $KIT && git mv a b"
t_prot "rm one kit file" allow "$T" "rm $KIT/commands/x.md"
t_prot "rm -rf kit/commands" deny "$T" "rm -rf $KIT/commands"
t_prot "rm -rf kit/commands/*" deny "$T" "rm -rf $KIT/commands/*"
t_prot "rm -rf a layer folder" deny "$T" "rm -rf $KIT/layers/mine"
t_prot "rm -rf kit/.git" deny "$T" "rm -rf $KIT/.git"
t_prot "rm -rf layer-declared path" deny "$T" "rm -rf /tmp/layer-protected-sample"
t_prot "grep config file | sort; rm -f /tmp/a" allow "$T" "grep x ~/.claude/CLAUDE.md | sort; rm -f /tmp/a"
t_prot "rm -rf ~/.claude/rules/*" deny "$T" "rm -rf ~/.claude/rules/*"
t_prot "rm -rf ~/.claude/projects/X/memory/*" deny "$T" "rm -rf ~/.claude/projects/X/memory/*"
t_prot "rm -rf a subfolder of a protected-paths dir" allow "$T" "rm -rf ~/Notes/inner"
t_prot "rm -rf the kit" deny "$T" "rm -rf $KIT"
t_prot "rm -rf \$HOME/.claude" deny "$T" 'rm -rf $HOME/.claude'
t_prot "rm -rf ~/.claude/*" deny "$T" "rm -rf ~/.claude/*"
t_prot "rm -rf \${HOME}/.claude/commands" deny "$T" 'rm -rf ${HOME}/.claude/commands'
t_prot "mv ~/.claude/rules /tmp/r" deny "$T" "mv ~/.claude/rules /tmp/r"
t_prot "sudo rm -rf kit rules dir (relative)" deny "$T" "cd $KIT && sudo rm -rf rules"
t_prot "bash -c rm of the config" deny "$T" "bash -c 'rm -rf ~/.claude/agents'"
t_prot "find kit -delete" deny "$T" "find $KIT -name x -delete"
t_prot "find /tmp/zz -delete" allow "$T" "find /tmp/zz -name x -delete"
t_prot "git clean in the kit" deny "$T" "git -C $KIT clean -fdx"
t_prot "git clean -n in the kit (dry run)" allow "$T" "git -C $KIT clean -n"
t_prot "git clean in another repo" allow "$T" "git -C $FEATURE clean -fd"
t_prot "rm -rf ~/.claude/cache/x" allow "$T" "rm -rf ~/.claude/cache/x"
t_prot "rm -rf ~/.claude/projects/X/sessions/*" allow "$T" "rm -rf ~/.claude/projects/X/sessions/*"
t_prot "mv within /tmp" allow "$T" "mv /tmp/a /tmp/b"
t_prot "cp from config to /tmp" allow "$T" "cp ~/.claude/rules/a /tmp/a"
t_prot "cat of a config file" allow "$T" "cat ~/.claude/rules/a.md"
t_prot "heredoc body mentioning rm -rf" allow "$T" $'cat > /tmp/n.txt <<EOF\nrm -rf ~/.claude/rules\nEOF'
t_prot "sed -i on a kit file (reminder only)" reminder "$T" "sed -i s/a/b/ $KIT/rules/x.md"
t_prot "redirect into config (reminder only)" reminder "$T" "echo hi > ~/.claude/rules/new.md"
t_prot "git commit in the kit (reminder only)" reminder "$KIT" "git commit -m x"
t_prot "redirect to /tmp" allow "$T" "echo hi > /tmp/new.md"

# --- protected-paths folders: the folder, its ancestors and .git, not what is inside
t_prot "rm -rf the protected-paths folder" deny "$T" "rm -rf ~/Notes"
t_prot "rm -rf its .git" deny "$T" "rm -rf ~/Notes/.git"
t_prot "mv the folder away" deny "$T" "mv ~/Notes /tmp/n"
t_prot "rm a file inside" allow "$T" "rm ~/Notes/inner/old.md"
t_prot "mv a file inside" allow "$T" "mv ~/Notes/a.md ~/Notes/b.md"
t_prot "rm -rf ~/Notes/*.md" allow "$T" "rm -f ~/Notes/*.md"
t_prot "rm -rf the parent of the folder" deny "$T" "rm -rf ~"
t_prot "find inside a protected folder" allow "$T" "find ~/Notes/inner -name '*.tmp' -delete"
# --- xargs, find, rsync, scripts, other delete verbs
t_prot "xargs rm of the config" deny "$T" "ls | xargs -n 1 rm -rf ~/.claude/commands"
t_prot "xargs -I rm of the kit folder" deny "$T" "echo x | xargs -I{} rm -rf $KIT/commands"
t_prot "xargs rm of /tmp" allow "$T" "echo x | xargs rm -rf /tmp/zz"
t_prot "find -exec rm of the config" deny "$T" "find /tmp -maxdepth 0 -exec rm -rf ~/.claude/rules \;"
t_prot "find home -delete" deny "$T" "find ~ -name '*.tmp' -delete"
t_prot "find home -exec rm" deny "$T" "find ~ -name '*.tmp' -exec rm {} +"
t_prot "find /tmp/zz -exec rm" allow "$T" "find /tmp/zz -name x -exec rm {} +"
t_prot "rsync --delete into the config" deny "$T" "rsync -a --delete /tmp/src/ ~/.claude/commands/"
t_prot "rsync --delete-after into the kit" deny "$T" "rsync -a --delete-after /tmp/src/ $KIT/rules/"
t_prot "rsync --delete into /tmp" allow "$T" "rsync -a --delete /tmp/src/ /tmp/dst/"
t_prot "rsync without --delete into the config" allow "$T" "rsync -a /tmp/src/ ~/.claude/cache/"
t_prot "trash of the config" deny "$T" "trash ~/.claude/rules"
t_prot "gio trash of the config" deny "$T" "gio trash ~/.claude/agents"
t_prot "busybox rm of the config" deny "$T" "busybox rm -rf ~/.claude/skills"
t_prot "trash of /tmp" allow "$T" "trash /tmp/zz"
t_prot "sh -c via here-string" deny "$T" "sh <<< 'rm -rf ~/.claude/rules'"
t_prot "cat of a here-string is only text" allow "$T" "cat <<< 'rm -rf ~/.claude/rules'"
t_prot "python -c rmtree of the config" deny "$T" "python3 -c 'import shutil; shutil.rmtree(\"$CFG/rules\")'"
t_prot "python -c rmtree of ~" deny "$T" "python3 -c 'import shutil,os; shutil.rmtree(os.path.expanduser(\"~/.claude/commands\"))'"
t_prot "perl -e unlink in the kit" deny "$T" "perl -e 'unlink(\"$KIT/commands\")'"
t_prot "python -c rmtree of /tmp" allow "$T" "python3 -c 'import shutil; shutil.rmtree(\"/tmp/zz\")'"
t_prot "python -c reading the config" allow "$T" "python3 -c 'print(open(\"$CFG/CLAUDE.md\").read())'"
t_prot "eval rm of the config" deny "$T" "eval 'rm -rf ~/.claude/rules'"

# ------------------------------------------------------------------ protect-config (Edit/Write)
t_file "Edit ~/.claude/rules/x.md (reminder)" reminder Edit "$CFG/rules/x.md"
t_file "Write to a kit file (reminder)" reminder Write "$KIT/rules/y.md"
t_file "MultiEdit on memory (reminder)" reminder MultiEdit "$CFG/projects/X/memory/m.md"
t_file "Write to a random /tmp file" allow Write "/tmp/some-random-file.txt"
t_file "Edit of a non-config ~/.claude file" allow Edit "$CFG/cache/x.json"
t_file "reminder first time in a session" reminder Edit "$CFG/rules/a.md" once1
t_file "reminder silent the second time" allow Edit "$CFG/rules/b.md" once1
t_file "Write settings.local.json (reminder)" reminder Write "$CFG/settings.local.json"
t_file "Edit the kit manifest (reminder)" reminder Edit "$CFG/.claude-kit-manifest"
t_file "Edit protected-paths (reminder)" reminder Edit "$CFG/protected-paths"
t_file "Write a plugin file (reminder)" reminder Write "$CFG/plugins/p/x.json"
t_file "Write a hook (reminder)" reminder Write "$CFG/hooks/h.sh"
t_file "Edit via another home's .claude" reminder Edit "/home/other/.claude/rules/x.md"
t_file "Edit a config file by relative path" allow Edit "cache/x.json"

t_guard "allowed remote: commit on main" allow "$ALLOWED" "git commit -m x"
t_guard "allowed remote: push origin main" allow "$ALLOWED" "git push origin main"
t_guard "allowed remote (config file): push" allow "$ALLOWED2" "git push origin master"
t_guard "allowed remote: force push stays denied" deny "$ALLOWED" "git push --force origin main"
t_guard "allowed remote: +refspec stays denied" deny "$ALLOWED" "git push origin +main"
t_guard "allowed remote: --mirror stays denied" deny "$ALLOWED" "git push --mirror"
t_guard "allowed remote: git -C from elsewhere" allow "$MASTER" "git -C $ALLOWED push origin main"
t_guard "unlisted remote: commit on main" deny "$OTHER" "git commit -m x"
t_guard "unlisted remote: push to main" deny "$OTHER" "git push origin main"
t_guard "no remote at all: commit on master" deny "$MASTER" "git commit -m x"

echo
echo "hooks.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
