#!/bin/bash
# Refuse a Read, or a Bash command that reads, a credential file, so the
# secret never enters the context. Creating one stays allowed: a redirect
# target (`> .env`) does not count. Example and template files pass.
#
# Bash is judged per pipeline, not per command line. A command that names the
# file without printing it (ls, stat, chmod) passes, and so do the forms that
# print no values: a count or match test (grep -c/-l/-L/-q), key names only
# (grep -o '^[A-Z_]*', cut -d= -f1, sed 's/=.*//', awk -F= '{print $1}'), or a
# pipeline that ends in one of those or in wc. Key names apply to .env files
# only. Anything else that reads it is refused.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
TARGET=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // ""')

CREDENTIAL_FILE='(^|/)(\.env(\.[A-Za-z0-9_-]+)?|id_(rsa|dsa|ecdsa|ed25519)|[^/]*\.pem|\.netrc|\.credentials\.json|\.git-credentials)$'
TEMPLATE='\.(example|sample|template)$'
READERS='(^|[;&|(`"'"'"']|\s)(cat|less|more|head|tail|bat|grep|rg|awk|sed|source|xxd|strings|base64|cut|sort|diff|jq|\.)\s'

# Stages that print no secret value. Character classes may not hold `=` or
# `:` so a key-name pattern cannot run on into the value.
Q='["'"'"']?'
SAFE_STAGE=(
  "(^|\s)grep\s+([^|]*\s)?-[A-Za-z]*[clLq][A-Za-z]*(\s|$)"
  "(^|\s)grep\s+([^|]*\s)?-[A-Za-z]*o[A-Za-z]*\s+${Q}\^\[[A-Za-z0-9_-]+\](\[[A-Za-z0-9_-]+\])?[*+]?${Q}(\s|$)"
  "(^|\s)cut\s+(-d\s*${Q}=${Q}\s+-f\s*1|-f\s*1\s+-d\s*${Q}=${Q})(\s|$)"
  "(^|\s)sed\s+(-E\s+)?${Q}s/=\.\*//g?${Q}(\s|$)"
  "(^|\s)awk\s+-F\s*${Q}=${Q}\s+${Q}\{\s*print \\\$1;?\s*\}${Q}(\s|$)"
)
SAFE_TAIL='^\s*wc(\s|$)'
# Key-name forms assume KEY=VALUE lines. On a key file, a .netrc or JSON they
# print the secret itself, so there only counts and match tests pass.
DOTENV='(^|/)\.env(\.[A-Za-z0-9_-]+)?$'

names_credential() { # names_credential <text>: print the first credential file it names
  local word
  set -f
  for word in $1; do
    word=${word//[\"\'\`]/}
    if echo "$word" | grep -qE "$CREDENTIAL_FILE" && ! echo "$word" | grep -qE "$TEMPLATE"; then
      echo "$word"
      return 0
    fi
  done
  return 1
}

is_safe_stage() { # is_safe_stage <stage> <file>
  local re
  echo "$2" | grep -qE "$DOTENV" || {
    echo "$1" | grep -qE "${SAFE_STAGE[0]}"
    return
  }
  for re in "${SAFE_STAGE[@]}"; do
    echo "$1" | grep -qE "$re" && return 0
  done
  return 1
}

block() {
  echo "BLOCKED: '$1' is a credential file. Do not read credential files. Read one secret with: ${HOOK_SECRET_TOOL:-<secret-tool>} <service> [field]. Counts and key names pass: grep -c, grep -o '^[A-Z_]*', cut -d= -f1." >&2
  exit 2
}

if [[ "$TOOL" != "Bash" ]]; then
  hit=$(names_credential "$TARGET") && block "$hit"
  exit 0
fi

echo "$TARGET" | grep -qE "$READERS" || exit 0
CMD=$(echo "$TARGET" | sed -E 's/>>?[[:space:]]*[^[:space:];&|]+//g')

while IFS= read -r pipeline; do
  names_credential "$pipeline" >/dev/null || continue
  IFS='|' read -ra stages <<<"$pipeline"
  last=${stages[${#stages[@]} - 1]}
  file=$(names_credential "$pipeline")
  if [[ "${#stages[@]}" -gt 1 ]] && { is_safe_stage "$last" "$file" || echo "$last" | grep -qE "$SAFE_TAIL"; }; then
    continue
  fi
  for stage in "${stages[@]}"; do
    hit=$(names_credential "$stage") || continue
    echo "$stage" | grep -qE "$READERS" || continue
    is_safe_stage "$stage" "$hit" || block "$hit"
  done
done < <(echo "$CMD" | sed -E 's/(&&|\|\||;)/\n/g')

exit 0
