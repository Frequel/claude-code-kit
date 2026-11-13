#!/usr/bin/env bash
# Tests for the plugin declarations merged by install.sh (plugins.json in the core and in layers).
# Every case runs against a throw-away CLAUDE_CONFIG_DIR and a throw-away copy of the kit.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; }
check(){ if eval "$2"; then ok; else bad "$1"; fi; }

new_world() { # $1 = name; creates $W/kit (copy of the kit without layers) and $W/home/.claude
  W="$(mktemp -d)"; mkdir -p "$W/home/.claude" "$W/kit/layers"
  cp -r "$HERE"/{install.sh,hooks,rules,commands,agents,skills,templates} "$W/kit/" 2>/dev/null
  mkdir -p "$W/kit/layers/t"; echo '{"name":"t","description":"test","requires":[]}' > "$W/kit/layers/t/layer.json"
  cat > "$W/kit/layers/t/plugins.json" <<'JSON'
{"marketplaces":{"m1":{"source":{"source":"github","repo":"o/r"}}},"plugins":["p1@m1"]}
JSON
}
run() { HOME="$W/home" CLAUDE_CONFIG_DIR="$W/home/.claude" bash "$W/kit/install.sh" --layers t >/dev/null 2>&1; }
get() { python3 -I -c "import json,sys;d=json.load(open('$W/home/.claude/settings.json'));print(json.dumps(eval(sys.argv[1]),sort_keys=True))" "$1"; }

# 1. a fresh install declares the marketplace and enables the plugin
new_world; run
check "fresh install enables the plugin" '[ "$(get "d[\"enabledPlugins\"]")" = "{\"p1@m1\": true}" ]'
check "fresh install registers the marketplace" '[ "$(get "d[\"extraKnownMarketplaces\"][\"m1\"][\"source\"][\"repo\"]")" = "\"o/r\"" ]'

# 2. running it again changes nothing
before="$(cat "$W/home/.claude/settings.json")"; run
check "second run is idempotent" '[ "$before" = "$(cat "$W/home/.claude/settings.json")" ]'

# 3. a plugin the user disabled stays disabled
python3 -I - "$W/home/.claude/settings.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['enabledPlugins']['p1@m1']=False; json.dump(d,open(p,'w'))
PY
run
check "a disabled plugin is not re-enabled" '[ "$(get "d[\"enabledPlugins\"][\"p1@m1\"]")" = "false" ]'

# 4. a marketplace the user registered under the same name is not replaced
python3 -I - "$W/home/.claude/settings.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['extraKnownMarketplaces']['m1']={'source':{'source':'github','repo':'mine/fork'}}; json.dump(d,open(p,'w'))
PY
run
check "a user marketplace is kept" '[ "$(get "d[\"extraKnownMarketplaces\"][\"m1\"][\"source\"][\"repo\"]")" = "\"mine/fork\"" ]'

# 5. other settings keys survive
python3 -I - "$W/home/.claude/settings.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['enabledPlugins']['other@x']=True; d['model']='opus'; json.dump(d,open(p,'w'))
PY
run
check "unrelated plugins and keys are kept" '[ "$(get "[d[\"enabledPlugins\"][\"other@x\"], d[\"model\"]]")" = "[true, \"opus\"]" ]'

# 6. --rules-only leaves plugins alone
new_world; HOME="$W/home" CLAUDE_CONFIG_DIR="$W/home/.claude" bash "$W/kit/install.sh" --layers t --rules-only >/dev/null 2>&1
check "--rules-only declares no plugin" '! grep -q enabledPlugins "$W/home/.claude/settings.json" 2>/dev/null'

# 7. the personal layer of this kit declares egm
check "personal layer declares egm@egm" 'python3 -I -c "import json;d=json.load(open(\"$HERE/layers/personal/plugins.json\"));assert \"egm@egm\" in d[\"plugins\"] and d[\"marketplaces\"][\"egm\"][\"source\"][\"repo\"]==\"google/elephant-goldfish-model\"" 2>/dev/null || [ ! -d "$HERE/layers/personal" ]'

echo "plugins: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
