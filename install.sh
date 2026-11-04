#!/usr/bin/env bash
# Install the kit into the user-level Claude Code configuration (~/.claude).
#
# Symlinks by default, so `git pull` in this repo updates every machine at once and the
# copies can never drift — which is the failure this kit exists to end. Use --copy when
# symlinks are not an option (see README, Cowork sessions).
#
# The kit is a generic core plus optional LAYERS. A layer is a folder under layers/<name>/ with
# the same shape as the core (rules/, commands/, agents/, skills/, hooks/hooks.json,
# hooks/scripts/) and a layer.json. Layers are where a person or a team keeps its own
# specialisations: they install exactly like the core, later layers win on a name clash, and
# each layer is normally its own git repository (the core ignores layers/* except layers/example).
# Pick them with --layers a,b; the choice is remembered in ~/.claude/.claude-kit-layers.
#
# The same ~/.claude is bind-mounted into the dev containers, where $HOME is /home/vscode
# instead of the host's /home/<user>. Everything written here must therefore resolve in both:
# symlinks are RELATIVE (~/.claude and the kit sit at the same relative position on both sides),
# manifest entries are relative to ~/.claude, and hook commands say $HOME instead of an
# absolute path.
#
# Nothing outside the manifest is ever touched: a file of yours with the same name is
# reported and left alone.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MANIFEST="$CLAUDE_DIR/.claude-kit-manifest"
LAYERS_FILE="$CLAUDE_DIR/.claude-kit-layers"
MODE="install"
MIGRATED=0
COPY=0
RULES_ONLY=0
LAYERS_ARG=""
LAYERS=()

usage() {
  cat <<'USAGE'
usage: install.sh [--user] [--layers a,b] [--copy] [--rules-only] [--uninstall] [--check] [--list-layers]

  --user          install commands, skills, agents, rules and hooks into ~/.claude (default)
  --layers a,b    also install these layers from layers/<name>/, in this order (later wins);
                  remembered in ~/.claude/.claude-kit-layers. --layers none installs the core only.
  --copy          copy files instead of symlinking them
  --rules-only    install only rules/ (use with plugin mode: plugins cannot ship rules)
  --uninstall     remove exactly what the manifest lists, and the kit's hooks
  --check         report what is installed, missing, broken or drifted — changes nothing
  --list-layers   show the layers available under layers/ and the ones in use
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user) MODE="install" ;;
    --copy) COPY=1 ;;
    --rules-only) RULES_ONLY=1 ;;
    --uninstall) MODE="uninstall" ;;
    --check) MODE="check" ;;
    --list-layers) MODE="list" ;;
    --layers)
      [ $# -ge 2 ] || { echo "--layers needs a value" >&2; exit 2; }
      LAYERS_ARG="$2"; shift ;;
    --layers=*) LAYERS_ARG="${1#--layers=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

skipped=0 installed=0

# An older kit named its manifest .<name>-kit-manifest: adopt it once, keep it as .bak.
migrate_manifest() {
  [ ! -f "$MANIFEST" ] || return 0
  local old
  for old in "$CLAUDE_DIR"/.*-kit-manifest; do
    [ -f "$old" ] || continue
    cp "$old" "$MANIFEST"
    mv "$old" "$old.bak"
    echo "  migrated $old to $MANIFEST (old file kept as .bak)"
    MIGRATED=1
    return 0
  done
  return 0
}

# Layer names are folder names: refuse anything that could escape layers/.
valid_layer_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

MISSING_LAYERS=0
resolve_layers() { # $1 = lenient: warn about a missing layer instead of stopping (used by --check)
  local raw="" n
  if [ -n "$LAYERS_ARG" ]; then raw="$LAYERS_ARG"
  elif [ -f "$LAYERS_FILE" ]; then raw="$(tr '\n' ',' < "$LAYERS_FILE")"
  fi
  [ "$raw" != "none" ] || raw=""
  LAYERS=()
  local IFS=','
  for n in $raw; do
    [ -n "$n" ] || continue
    valid_layer_name "$n" || { echo "invalid layer name: $n" >&2; exit 2; }
    if [ ! -d "$KIT_ROOT/layers/$n" ]; then
      echo "layer not found: $KIT_ROOT/layers/$n (clone or create it first)" >&2
      [ "${1:-}" = "lenient" ] || exit 2
      MISSING_LAYERS=$((MISSING_LAYERS+1)); continue
    fi
    LAYERS+=("$n")
  done
}

check_layer_requirements() { # warn when a layer.json "requires" names a layer that is not in use
  [ "${#LAYERS[@]}" -gt 0 ] || return 0
  python3 - "$KIT_ROOT" "${LAYERS[@]}" <<'PY'
import json, pathlib, sys
kit, used = pathlib.Path(sys.argv[1]), sys.argv[2:]
for name in used:
    meta = kit / "layers" / name / "layer.json"
    if not meta.exists():
        print(f"  warning: layer {name} has no layer.json")
        continue
    try:
        req = json.loads(meta.read_text()).get("requires", [])
    except ValueError:
        print(f"  warning: layer {name}: layer.json is not valid JSON")
        continue
    for r in req:
        if r not in used:
            print(f"  warning: layer {name} requires layer {r}, which is not in use")
PY
}

# Manifest entries are relative to $CLAUDE_DIR. Older manifests hold absolute paths written
# on the host or in a container; strip everything up to the config dir's name so both forms
# compare equal.
manifest_entries() {
  [ -f "$MANIFEST" ] || return 0
  local base p
  base="$(basename "$CLAUDE_DIR")"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in /*) p="${p##*/"$base"/}" ;; esac
    echo "$p"
  done < "$MANIFEST"
}

install_entry() { # $1 = source path, $2 = destination relative to $CLAUDE_DIR
  local src="$1" rel="$2" dst="$CLAUDE_DIR/$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ "$COPY" -eq 0 ] && [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ] \
       && [ "$(readlink "$dst")" = "$(realpath -s --relative-to="$(dirname "$dst")" "$src")" ]; then
      echo "$rel" >> "$MANIFEST.new"; return
    fi
    # Not `| grep -q`: grep -q exits on the first match, the producer dies of SIGPIPE, and
    # pipefail turns a found entry into "not ours".
    if grep -xF "$rel" "$MANIFEST.new" >/dev/null 2>&1; then
      rm -rf "$dst"                      # laid down earlier in this run by a lower layer: the later layer wins
      echo "  override (later layer wins): $rel"
    elif manifest_entries | grep -xF "$rel" >/dev/null && { [ -L "$dst" ] || [ "$COPY" -eq 1 ]; }; then
      rm -rf "$dst"                      # ours from a previous run (a link, or a copy in --copy mode): replace
    else
      echo "  skip (your own file wins; a listed entry that is no longer a link is yours): $rel"; skipped=$((skipped+1)); return
    fi
  fi
  if [ "$COPY" -eq 1 ]; then
    cp -rf "$src" "$dst"
  else
    # Relative, without resolving symlinks: valid wherever ~/.claude and the kit keep the
    # same relative position, which is true on the host and in every dev container.
    ln -s "$(realpath -s --relative-to="$(dirname "$dst")" "$src")" "$dst"
  fi
  echo "$rel" >> "$MANIFEST.new"; installed=$((installed+1))
}

install_tree() { # $1 = a kit root (the kit itself or one layer)
  local root="$1" f d
  for f in "$root"/rules/*.md; do [ -e "$f" ] && install_entry "$f" "rules/$(basename "$f")"; done
  [ "$RULES_ONLY" -eq 1 ] && return 0
  for f in "$root"/commands/*.md; do [ -e "$f" ] && install_entry "$f" "commands/$(basename "$f")"; done
  for f in "$root"/agents/*.md;   do [ -e "$f" ] && install_entry "$f" "agents/$(basename "$f")"; done
  for d in "$root"/skills/*/;     do [ -d "$d" ] && install_entry "${d%/}" "skills/$(basename "${d%/}")"; done
  return 0
}

# How hook commands refer to the kit: through $HOME when the kit lives under it, so the same
# settings.json works on the host and in a container. Hook commands run through a shell, which
# expands it.
kit_ref() {
  case "$KIT_ROOT/" in
    "$HOME"/*) echo "\$HOME/${KIT_ROOT#"$HOME"/}" ;;
    *) echo "$KIT_ROOT" ;;
  esac
}

merge_hooks() { # add the core's hooks, then each layer's, to settings.json, idempotently
  python3 - "$KIT_ROOT" "$(kit_ref)" "$CLAUDE_DIR/settings.json" "${LAYERS[@]}" <<'PY'
import json, os, sys, pathlib
kit, ref, settings_path = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
layers = sys.argv[4:]
# Recognises every hook this kit wrote, by its full path (absolute or $HOME form): the core, any
# layer, and the old personal/ folder. A hook of another checkout is never touched.
markers = tuple(f"{b}/{t}" for b in {kit, ref} for t in ("hooks/scripts/", "layers/", "personal/hooks/scripts/"))
sources = [pathlib.Path(kit)/'hooks'/'hooks.json'] + [pathlib.Path(kit)/'layers'/l/'hooks'/'hooks.json' for l in layers]
settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
cur = settings.setdefault('hooks', {})
# Remove old kit hooks one by one, never a whole group: a group may also hold someone else's hook.
for event, groups in list(cur.items()):
    for g in list(groups):
        g['hooks'] = [h for h in g.get('hooks', []) if not any(m in (h.get('command') or '') for m in markers)]
        if not g['hooks']:
            groups.remove(g)
    if not groups:
        del cur[event]
added = 0
for src in sources:
    if not src.exists():
        continue
    for event, groups in json.loads(src.read_text())['hooks'].items():
        for group in groups:
            # A layer's hooks.json says ${CLAUDE_PLUGIN_ROOT}/layers/<name>/hooks/scripts/x.sh
            cur.setdefault(event, []).append(json.loads(json.dumps(group).replace('${CLAUDE_PLUGIN_ROOT}', ref)))
            added += 1
settings_path.write_text(json.dumps(settings, indent=2) + '\n')
print(f"  hooks merged into settings.json ({added} group(s), kit referenced as {ref})")
PY
}

remove_hooks() {
  python3 - "$KIT_ROOT" "$(kit_ref)" "$CLAUDE_DIR/settings.json" <<'PY'
import json, os, sys, pathlib
kit, ref, settings_path = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
if not settings_path.exists(): sys.exit(0)
markers = tuple(f"{b}/{t}" for b in {kit, ref} for t in ("hooks/scripts/", "layers/", "personal/hooks/scripts/"))
settings = json.loads(settings_path.read_text())
removed = 0
for event, groups in list(settings.get('hooks', {}).items()):
    for g in list(groups):
        before = len(g.get('hooks', []))
        g['hooks'] = [h for h in g.get('hooks', []) if not any(m in (h.get('command') or '') for m in markers)]
        removed += before - len(g['hooks'])
        if not g['hooks']: groups.remove(g)
    if not groups: del settings['hooks'][event]
settings_path.write_text(json.dumps(settings, indent=2) + '\n')
print(f"  removed {removed} kit hook(s) from settings.json")
PY
}

kit_source() { # $1 = manifest entry → the kit file it comes from (last layer first, core last)
  local rel="$1" i
  for (( i=${#LAYERS[@]}-1; i>=0; i-- )); do
    if [ -e "$KIT_ROOT/layers/${LAYERS[$i]}/$rel" ]; then echo "$KIT_ROOT/layers/${LAYERS[$i]}/$rel"; return; fi
  done
  echo "$KIT_ROOT/$rel"
}

drop_stale_entries() { # entries of the previous manifest that this run did not lay down again
  local rel p
  while IFS= read -r rel; do
    grep -xF "$rel" "$MANIFEST.new" >/dev/null && continue
    p="$CLAUDE_DIR/$rel"
    # Only ever remove what is a link into the kit (or a dead link): never a plain file.
    if [ -L "$p" ] && { [ ! -e "$p" ] || [[ "$(readlink -f "$p")" == "$KIT_ROOT"/* ]]; }; then
      rm -f "$p" && echo "  removed stale entry: $rel"
    fi
  done < <(manifest_entries)
}

case "$MODE" in
list)
  echo "layers available in $KIT_ROOT/layers:"
  for d in "$KIT_ROOT"/layers/*/; do
    [ -d "$d" ] || continue
    printf '  %s\n' "$(basename "$d")"
  done
  resolve_layers
  echo "in use: ${LAYERS[*]:-(core only)}"
  ;;
install)
  migrate_manifest
  resolve_layers
  : > "$MANIFEST.new"
  echo "installing the kit from $KIT_ROOT into $CLAUDE_DIR (layers: ${LAYERS[*]:-none})"
  check_layer_requirements
  if [ "$MIGRATED" -eq 1 ] && [ -z "$LAYERS_ARG" ] && [ ! -f "$LAYERS_FILE" ]; then
    echo "  WARNING: this config was installed by an older kit that had a personal/ folder. No --layers given, so only"
    echo "           the core is installed and your old personal entries will be removed. Re-run with e.g."
    echo "           ./install.sh --layers personal,<other layers>   (see --list-layers)"
  fi
  install_tree "$KIT_ROOT"
  for l in "${LAYERS[@]}"; do install_tree "$KIT_ROOT/layers/$l"; done
  [ "$RULES_ONLY" -eq 0 ] && merge_hooks
  drop_stale_entries
  mv "$MANIFEST.new" "$MANIFEST"
  if [ "${#LAYERS[@]}" -gt 0 ]; then printf '%s\n' "${LAYERS[@]}" > "$LAYERS_FILE"; else rm -f "$LAYERS_FILE"; fi
  echo "installed $installed entr(ies), skipped $skipped. Manifest: $MANIFEST"
  echo "Restart Claude Code (or run /doctor) for the new hooks and rules to load."
  ;;
uninstall)
  migrate_manifest
  if [ -f "$MANIFEST" ]; then
    resolve_layers lenient
    while IFS= read -r rel; do
      p="$CLAUDE_DIR/$rel"
      if [ -L "$p" ] || { [ -e "$p" ] && diff -rq "$(kit_source "$rel")" "$p" >/dev/null 2>&1; }; then
        rm -rf "${CLAUDE_DIR:?}/$rel" && echo "  removed $rel"
      elif [ -e "$p" ]; then
        echo "  kept (no longer a link and differs from the kit: yours): $rel"
      fi
    done < <(manifest_entries)
    rm -f "$MANIFEST" "$LAYERS_FILE"
  else
    echo "no manifest at $MANIFEST — nothing to uninstall"
  fi
  remove_hooks
  ;;
check)
  migrate_manifest
  resolve_layers lenient
  echo "kit:     $KIT_ROOT"
  echo "target:  $CLAUDE_DIR"
  echo "layers:  ${LAYERS[*]:-none}"
  [ -f "$MANIFEST" ] || { echo "not installed (no manifest)"; exit 1; }
  missing=0 drifted=0 broken=0 absolute=0 ok=0
  while IFS= read -r rel; do
    p="$CLAUDE_DIR/$rel"; src="$(kit_source "$rel")"
    if [ -L "$p" ] && [ ! -e "$p" ]; then echo "  BROKEN   $rel -> $(readlink "$p")"; broken=$((broken+1))
    elif [ ! -e "$p" ]; then echo "  MISSING  $rel"; missing=$((missing+1))
    elif [ -L "$p" ]; then
      case "$(readlink "$p")" in
        /*) echo "  ABSOLUTE $rel (works here, breaks on the other side of the container mount)"; absolute=$((absolute+1)) ;;
        *) ok=$((ok+1)) ;;
      esac
    elif [ -e "$src" ] && ! diff -rq "$src" "$p" >/dev/null 2>&1; then echo "  DRIFTED  $rel"; drifted=$((drifted+1))
    else ok=$((ok+1)); fi
  done < <(manifest_entries)
  hooks_abs=$(python3 - "$KIT_ROOT" "$CLAUDE_DIR/settings.json" <<'PY'
import json, os, sys, pathlib
kit = sys.argv[1]
markers = tuple(f"{kit}/{t}" for t in ("hooks/scripts/", "layers/", "personal/hooks/scripts/"))
p = pathlib.Path(sys.argv[2])
s = json.loads(p.read_text()) if p.exists() else {}
cmds = [h.get('command') or '' for gs in s.get('hooks', {}).values() for g in gs for h in g.get('hooks', [])]
print(sum(1 for c in cmds if any(m in c for m in markers)))
PY
)
  [ "$hooks_abs" -gt 0 ] && echo "  $hooks_abs kit hook(s) use an absolute path: rerun ./install.sh"
  echo "  $ok ok, $drifted drifted, $missing missing, $broken broken, $absolute absolute"
  [ "$MISSING_LAYERS" -gt 0 ] && echo "  $MISSING_LAYERS selected layer(s) not found under layers/ (clone them or run ./install.sh --layers ...)"
  [ "$MISSING_LAYERS" -eq 0 ] && [ "$missing" -eq 0 ] && [ "$drifted" -eq 0 ] && [ "$broken" -eq 0 ] && [ "$absolute" -eq 0 ] && [ "$hooks_abs" -eq 0 ]
  ;;
esac
