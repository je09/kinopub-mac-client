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
comments_boundary_violations="$(count_matches '^(import KinoPubBackend|.*AppContext\.shared)' KinoPubAppleClient/Views/Comments -g '*.swift')"
search_boundary_violations="$(count_matches '^(import KinoPubBackend|.*AppContext\.shared)' KinoPubAppleClient/Views/Search -g '*.swift')"
# Phase 5: views must not perform persistence/filesystem work. Scope is the Phase-5 features
# (media detail, search, auth, downloads/storage); PlayerManager (Phase 6) and feature stores
# (DownloadsCatalog, ProfileModel) are tracked as reports, not blockers.
phase5_view_storage="$(count_matches '@AppStorage|UserDefaults' KinoPubAppleClient/Views/MediaItem KinoPubAppleClient/Views/Search KinoPubAppleClient/Views/Auth -g '*.swift' -g '!RecentSearchRepository.swift')"
phase5_view_filesystem="$(count_matches 'FileManager|NSHomeDirectory|attributesOfItem|enumerator' KinoPubAppleClient/Views/MediaItem KinoPubAppleClient/Views/Search KinoPubAppleClient/Views/Auth -g '*.swift')"
phase5_view_network="$(count_matches 'URLSession|NSWorkspace|NSPasteboard' KinoPubAppleClient/Views/MediaItem KinoPubAppleClient/Views/Search KinoPubAppleClient/Views/Auth -g '*.swift')"
media_detail_screen_lines="$(wc -l < KinoPubAppleClient/Views/MediaItem/MediaItemView.swift | tr -d ' ')"
search_screen_lines="$(wc -l < KinoPubAppleClient/Views/Search/SearchView.swift | tr -d ' ')"

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
| Comments boundary violations (blocking) | $comments_boundary_violations |
| Search boundary violations (blocking) | $search_boundary_violations |
| Phase-5 view UserDefaults/@AppStorage (blocking) | $phase5_view_storage |
| Phase-5 view filesystem calls (blocking) | $phase5_view_filesystem |
| Phase-5 view network/platform calls (blocking) | $phase5_view_network |
| Media detail screen lines (target <500) | $media_detail_screen_lines |
| Search screen lines (target <500) | $search_screen_lines |
| Swift source files over 500 lines | $large_file_count |

### Files over 500 lines

\`\`\`
${large_files:-None}
\`\`\`
REPORT

if [[ "$comments_boundary_violations" != "0" ]]; then
  echo "Comments must not import KinoPubBackend or access AppContext.shared" >&2
  exit 1
fi

if [[ "$search_boundary_violations" != "0" ]]; then
  echo "Search must not import KinoPubBackend or access AppContext.shared" >&2
  exit 1
fi

if [[ "$phase5_view_storage" != "0" ]]; then
  echo "Phase-5 views must not touch UserDefaults/@AppStorage" >&2
  exit 1
fi

if [[ "$phase5_view_filesystem" != "0" ]]; then
  echo "Phase-5 views must not touch the filesystem" >&2
  exit 1
fi

if [[ "$phase5_view_network" != "0" ]]; then
  echo "Phase-5 views must not perform network/platform calls" >&2
  exit 1
fi

if [[ "$media_detail_screen_lines" -gt 500 ]]; then
  echo "MediaItemView.swift must stay under 500 lines (Phase 5 gate)" >&2
  exit 1
fi

if [[ "$search_screen_lines" -gt 500 ]]; then
  echo "SearchView.swift must stay under 500 lines (Phase 5 gate)" >&2
  exit 1
fi
