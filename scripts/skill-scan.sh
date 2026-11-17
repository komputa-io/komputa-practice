#!/usr/bin/env bash
# Scans skills/ with NVIDIA SkillSpector, static analysis only (--no-llm: no model, no key).
#   scripts/skill-scan.sh [path]       (default: skills)
# Accepted findings are in .skillspector-baselines/<skill>.yaml, each with a reason. Any
# other finding fails the scan. SkillSpector reads the files and runs none of
# them; its git, URL and registry inputs are never used here. The scan runs
# with no network when the host lets a user make a network namespace.
# Exit 0: no active finding. 1: a finding. 2: install or usage error.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR
die() {
  printf 'skill-scan: %s\n' "$*" >&2
  exit 2
}

(($# <= 1)) || {
  printf 'usage: scripts/skill-scan.sh [path]\n' >&2
  exit 2
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target=${1:-$root/skills}
commit=$(sed -n 's/^commit=//p' "$root/scripts/skillspector.pin")
python=$(sed -n 's/^python=//p' "$root/scripts/skillspector.pin")
[[ $commit =~ ^[0-9a-f]{40}$ && $python =~ ^3\.[0-9]+$ ]] || die "scripts/skillspector.pin has no usable commit and python"

out=$(mktemp)
trap 'rm -f -- "$out"' EXIT
src="$root/.gate/skillspector-$commit"
bin="$src/.venv/bin/skillspector"
if [[ ! -x $bin ]]; then
  rm -rf "$src"
  mkdir -p "$src"
  git -C "$src" init -q
  git -C "$src" fetch -q --depth 1 https://github.com/NVIDIA/SkillSpector.git "$commit" || die "cannot fetch SkillSpector $commit"
  git -C "$src" checkout -q --detach FETCH_HEAD
  [[ $(git -C "$src" rev-parse HEAD) == "$commit" ]] || die "SkillSpector is not at the pinned commit"
  (cd "$src" && uv sync --frozen --no-dev --python "$python" --quiet) || die "cannot install SkillSpector"
fi

# A scan has no use for a network: run it in an empty network namespace when the host allows one.
run=()
if unshare -rn true 2>/dev/null; then
  run=(unshare -rn)
else
  printf 'skill-scan: no network namespace here; the scan runs with the host network\n' >&2
fi

# One scan for each skill: a baseline works on one skill, and .skillspector-baselines/<skill>.yaml
# holds the accepted findings of that skill only.
skills=()
if [[ -f $target/SKILL.md || -f $target/skill.md ]]; then
  skills=("$target")
else
  for d in "$target"/*/; do
    [[ -f $d/SKILL.md || -f $d/skill.md ]] && skills+=("${d%/}")
  done
fi
((${#skills[@]})) || die "no skill under $target"
failed=()
for d in "${skills[@]}"; do
  args=(scan "$d" --no-llm --fail-on-findings)
  base="$root/.skillspector-baselines/${d##*/}.yaml"
  [[ ! -f $base ]] || args+=(--baseline "$base")
  rc=0
  "${run[@]}" "$bin" "${args[@]}" >"$out" 2>&1 || rc=$?
  if ((rc == 0)); then
    printf 'skill-scan: %s: ok\n' "${d##*/}"
  else
    printf 'skill-scan: %s: exit %d\n' "${d##*/}" "$rc" >&2
    cat -- "$out" >&2
    failed+=("${d##*/}")
  fi
done
((${#failed[@]} == 0)) || {
  printf 'skill-scan: failed: %s\n' "${failed[*]}" >&2
  exit 1
}
