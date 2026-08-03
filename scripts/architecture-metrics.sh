#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

count_matches() {
  local pattern="$1"
  shift
  local output
  output="$(rg -n "$pattern" "$@" 2>/dev/null || true)"
  if [[ -z "$output" ]]; then
    echo 0
  else
    printf '%s\n' "$output" | wc -l | tr -d ' '
  fi
}

app_context_refs="$(count_matches 'AppContext\.shared' KinoPubAppleClient -g '*.swift')"
view_backend_imports="$(count_matches '^import KinoPubBackend$' KinoPubAppleClient/Views -g '*.swift')"
ui_backend_imports="$(count_matches '^import KinoPubBackend$' Packages/KinoPubUI/Sources -g '*.swift')"
transport_force_unwraps="$(count_matches '[)!]\!' Packages/KinoPubBackend/Sources -g '*.swift')"

large_files="$({ find KinoPubAppleClient Packages \
  -path '*/.build' -prune -o -type f -name '*.swift' -print0 \
  | xargs -0 wc -l \
  | awk '$1 > 500 && $2 != "total" { print $1 " " $2 }' \
  | sort -nr; } || true)"
large_file_count="$(if [[ -n "$large_files" ]]; then printf '%s\n' "$large_files" | wc -l | tr -d ' '; else echo 0; fi)"

cat <<REPORT
## Architecture baseline

| Metric | Count |
|---|---:|
| \`AppContext.shared\` references in app code | $app_context_refs |
| Views importing \`KinoPubBackend\` | $view_backend_imports |
| KinoPubUI files importing \`KinoPubBackend\` | $ui_backend_imports |
| Potential force unwraps in transport sources | $transport_force_unwraps |
| Swift source files over 500 lines | $large_file_count |

### Files over 500 lines

\`\`\`
${large_files:-None}
\`\`\`
REPORT
