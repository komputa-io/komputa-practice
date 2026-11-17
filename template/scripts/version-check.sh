#!/usr/bin/env bash
# The version check: a project has one semver version, with one source of truth.
# Managed by the project template; scripts/gate.sh runs it, and
# scripts/tag-release.sh asks it for the version.
#   scripts/version-check.sh [--print] [PATHSPEC ...]
# It reads these declarations in the tracked files (a PATHSPEC such as ':!archive/'
# leaves a folder out): pyproject.toml [project] version, package.json "version",
# Cargo.toml [package] or [workspace.package] version, <Version> in
# Directory.Build.props or a .csproj, a VERSION file, and a literal __version__ in a
# .py file. A derived version is no declaration: a dynamic pyproject version,
# version.workspace = true, importlib.metadata.
# It fails when a literal __version__ exists, when two declarations disagree, when a
# version is not semver, or when there is none. Equal copies pass.
# --print prints the one version and checks nothing else.
# Exit 0: one valid version. 1: a refusal, with the fix. 2: wrong arguments.
set -Eeuo pipefail
shopt -s inherit_errexit
trap 'printf "%s: line %d: %s exited %d\n" "${0##*/}" "$LINENO" "$BASH_COMMAND" "$?" >&2' ERR

print=0
if [[ "${1-}" == --print ]]; then
  print=1
  shift
fi
for a in "$@"; do
  [[ "$a" == :* ]] || {
    printf 'usage: scripts/version-check.sh [--print] [PATHSPEC ...]\n' >&2
    exit 2
  }
done

semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
# Test data and installed packages are not the project's own declarations.
not_own=(':(exclude,glob)**/node_modules/**' ':(exclude,glob)**/fixtures/**' ':(exclude,glob)**/__fixtures__/**'
  ':(exclude,glob)**/tests/**' ':(exclude,glob)**/test/**' ':(exclude,glob)**/testdata/**' ':(exclude,glob)**/.venv/**')

fail=()
decl=() # "path<TAB>value"
literal=()

# toml_version FILE TABLE...: the version = "x" line inside one of the tables.
toml_version() {
  local f=$1
  shift
  awk -v tables="$*" '
    BEGIN { n = split(tables, t, " "); for (i = 1; i <= n; i++) want["[" t[i] "]"] = 1 }
    /^[[:space:]]*\[/ { s = $0; gsub(/[[:space:]]/, "", s); on = (s in want); next }
    on && /^[[:space:]]*version[[:space:]]*=[[:space:]]*["\x27]/ {
      v = $0; sub(/^[^"\x27]*["\x27]/, "", v); sub(/["\x27].*$/, "", v); print v; exit }' "$f"
}

while IFS= read -r -d '' f; do
  v=''
  case "${f##*/}" in
    pyproject.toml) v=$(toml_version "$f" project) ;;
    Cargo.toml) v=$(toml_version "$f" package workspace.package) ;;
    package.json) v=$(sed -n -E 's/^(  |\t)"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2/p' "$f" | head -n 1) ;;
    VERSION) v=$(head -n 1 "$f" | tr -d '[:space:]') ;;
    Directory.Build.props | *.csproj) v=$(sed -n -E 's/.*<Version>[[:space:]]*([^<[:space:]]*)[[:space:]]*<\/Version>.*/\1/p' "$f" | head -n 1) ;;
    *.py)
      lit=$(sed -n -E "s/^__version__[[:space:]]*(:[^=]*)?=[[:space:]]*[\"']([^\"']*)[\"'].*/\2/p" "$f" | head -n 1)
      [[ -z "$lit" ]] || literal+=("$f"$'\t'"$lit")
      continue
      ;;
    *) continue ;;
  esac
  [[ -z "$v" ]] || decl+=("$f"$'\t'"$v")
done < <(git ls-files -z -- '*.py' '*pyproject.toml' '*Cargo.toml' '*package.json' '*VERSION' '*Directory.Build.props' '*.csproj' "${not_own[@]}" "$@")

if ((print)); then
  ((${#decl[@]} > 0)) || exit 1
  printf '%s\n' "${decl[0]#*$'\t'}"
  exit 0
fi

for l in "${literal[@]}"; do
  f=${l%%$'\t'*}
  others=''
  for d in "${decl[@]}"; do others+="${others:+, }${d%%$'\t'*}=${d#*$'\t'}"; done
  fail+=("$f holds a literal __version__ ${l#*$'\t'}${others:+ beside the declared $others}. Read it from the installed package instead: from importlib.metadata import version; __version__ = version('<package name>'). Then the version lives only in pyproject.toml.")
done

if ((${#decl[@]} == 0)); then
  fail+=("no version declared. Add one: [project] version = \"0.1.0\" in pyproject.toml, \"version\" in package.json, version in Cargo.toml, <Version> in Directory.Build.props, or a VERSION file with 0.1.0. A repo that ships no software sets the copier answer versioned to false (copier update, then answer it).")
fi

first=''
differ=0
for d in "${decl[@]}"; do
  p=${d%%$'\t'*} v=${d#*$'\t'}
  [[ "$v" =~ $semver ]] || fail+=("$p: version '$v' is not semver. Use MAJOR.MINOR.PATCH, with an optional -pre-release, for example 1.4.0 or 2.0.0-rc.1.")
  [[ -n "$first" ]] || first=$v
  [[ "$v" == "$first" ]] || differ=1
done
if ((differ)); then
  list=''
  for d in "${decl[@]}"; do list+="${list:+, }${d%%$'\t'*}=${d#*$'\t'}"; done
  fail+=("the version is declared more than once and the copies differ: $list. Keep one source, set the others to the same value, and derive the rest: importlib.metadata in Python, version.workspace = true in Cargo, a read of package.json in JavaScript (docs: versioning). A repo of independent packages answers versioned: false (copier update).")
fi

if ((${#fail[@]} > 0)); then
  for m in "${fail[@]}"; do printf 'version-check: %s\n' "$m" >&2; done
  exit 1
fi
printf 'version-check: %s (%d declaration(s))\n' "$first" "${#decl[@]}"
