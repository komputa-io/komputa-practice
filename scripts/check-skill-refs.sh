#!/usr/bin/env bash
# check-skill-refs.sh [skill-dir ...]: fail when a skill in skills/ names an
# installed skill that is no longer installed (skills/CONVENTIONS.md).
#
# House skills name other skills only as pointers, written in backticks as
# `plugin:skill` (an installed plugin's skill) or `house-<name>` (another house
# skill). A rename upstream then fails this check instead of going stale.
#
# - `plugin:skill`: when the plugin is installed, its install path must hold
#   <skill>/SKILL.md; missing is an error. A prefix that is not an installed
#   plugin is a warning: it can be an image tag (`postgres:latest`) or a plugin
#   that was removed.
# - `house-<name>`: a folder in skills/. Missing is a warning, because a house
#   skill can be planned or on another branch.
#
# With no arguments it checks every folder in skills/. Without Claude Code's
# installed-plugins list (a CI container has none) it checks nothing and says so.
# Exit codes: 0 no error (also with no list); 1 a named skill is missing.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills"
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
installed="$config/plugins/installed_plugins.json"
[[ -f "$installed" ]] || {
  echo "skill refs: skipped, no $installed (Claude Code's plugin list)"
  exit 0
}

if [[ $# -gt 0 ]]; then
  dirs=("$@")
else
  mapfile -t dirs < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
fi
[[ ${#dirs[@]} -gt 0 ]] || {
  echo "skill refs: no skills found"
  exit 0
}

errors=0 warnings=0

# install_path <plugin>: the active install path of a plugin, or nothing.
install_path() {
  jq -r --arg p "$1" '.plugins | to_entries[]
    | select(.key | split("@")[0] == $p) | .value[0].installPath' "$installed" | head -1
}

for dir in "${dirs[@]}"; do
  skill=$(basename "$dir")
  # shellcheck disable=SC2016 # the backticks in the grep pattern are literal Markdown
  while IFS=: read -r file line ref; do
    if [[ $ref == house-* ]]; then
      [[ $ref == "$skill" ]] && continue
      if [[ ! -d "$root/$ref" ]]; then
        echo "warn  ${file#"$root"/}:$line names \`$ref\`, not in this checkout"
        warnings=$((warnings + 1))
      fi
      continue
    fi
    plugin=${ref%%:*} name=${ref#*:}
    path=$(install_path "$plugin")
    if [[ -z "$path" ]]; then
      # Not a plugin here: an image tag (`postgres:latest`) or a removed plugin.
      echo "warn  ${file#"$root"/}:$line names \`$ref\`: $plugin is not an installed plugin"
      warnings=$((warnings + 1))
    elif [[ -z "$(find "$path" -path "*/$name/SKILL.md" -print -quit 2>/dev/null)" ]]; then
      echo "ERROR ${file#"$root"/}:$line names \`$ref\`: $plugin has no skill $name"
      errors=$((errors + 1))
    fi
  done < <(grep -rnoE '`([a-z0-9-]+:[a-z0-9-]+|house-[a-z0-9-]+)`' "$dir" --include='*.md' \
    | sed -E 's/`//g')
done

echo "skill refs: $errors error(s), $warnings warning(s)"
[[ "$errors" -eq 0 ]]
