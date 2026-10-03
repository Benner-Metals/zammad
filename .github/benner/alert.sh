#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Opens one GitHub issue per upstream event the Benner build has to react to:
#   - a new upstream build on the branch of its release line;
#   - a newer Zammad release line on upstream stable.
#
# Expects the KEY=value outputs of upstream-state.sh and rebase-onto-upstream.sh --trial as
#   upper-case environment variables, GH_TOKEN, and optionally ALERT_ASSIGNEE.

# Single-quoted backticks are literal Markdown or shell hints.
# shellcheck disable=SC2016

set -o errexit
set -o nounset
set -o pipefail

LABEL=benner-upstream
IMAGE=ghcr.io/benner-metals/zammad

gh label create "$LABEL" --color 0e8a16 --description 'Upstream Zammad changes for the Benner build' > /dev/null 2>&1 || true

open_issue() {
  local title=$1 body=$2 titles number

  # A failed lookup stops the run instead of risking a duplicate issue.
  titles=$(gh issue list --label "$LABEL" --state all --search "\"${title}\" in:title" --limit 100 --json title --jq '.[].title')
  if grep -Fxq "$title" <<< "$titles"; then
    echo "Issue already exists: ${title}"
    return
  fi

  number=$(gh issue create --label "$LABEL" --title "$title" --body "$body" | sed 's|.*/||')
  echo "Opened issue #${number}: ${title}"

  if [ -n "${ALERT_ASSIGNEE:-}" ]; then
    gh issue edit "$number" --add-assignee "$ALERT_ASSIGNEE" > /dev/null || echo "Could not assign ${ALERT_ASSIGNEE}."
  fi
}

# Hints for the exit condition: production returns to the official image once a release
#   contains both Benner features.
upstream_markers() {
  local ref=$1 migration

  if git grep -q move_to_folder_id "$ref" -- app/models/channel/driver/microsoft_graph_inbound.rb; then
    echo '- the Graph inbound driver knows `move_to_folder_id` (move-to-folder)'
  fi
  if git cat-file -e "${ref}:lib/microsoft_cloud.rb" 2> /dev/null; then
    echo '- `lib/microsoft_cloud.rb` exists (national clouds)'
  fi
  for migration in $(git ls-tree -r --name-only "$ref" -- db/migrate | grep -F add_microsoft_cloud_selection || true); do
    echo "- migration \`${migration}\` exists; reconcile it with the Benner migration"
  done
}

if [ "$UPSTREAM_BASE" != "$UPSTREAM_TIP" ]; then
  case "${TRIAL_RESULT:-${TRIAL_OUTCOME:-}}" in
    clean) trial='applies cleanly.' ;;
    catalog) trial='applies; only `i18n/zammad.pot` conflicts, which the rebase script regenerates.' ;;
    conflict)
      if [ -n "${TRIAL_CONFLICTS:-}" ]; then
        trial="**conflicts** in \`${TRIAL_CONFLICTS}\`; resolve them by hand."
      else
        trial='**stopped** without reporting conflicting files; rebase by hand.'
      fi
      ;;
    failure) trial="**failed**; see [the workflow run](${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-Benner-Metals/zammad}/actions/runs/${GITHUB_RUN_ID:-})." ;;
    *) trial='did not run.' ;;
  esac
  if [ "${TRIAL_DROPPED:-0}" -gt 0 ]; then
    trial="${trial} ${TRIAL_DROPPED} Benner commit(s) became empty, so upstream already contains them: ${TRIAL_DROPPED_SUBJECTS:-unknown}"
  fi

  markers=$(upstream_markers "$UPSTREAM_TIP")
  log=$(git log --max-count=50 --oneline --no-decorate "${UPSTREAM_BASE}..${UPSTREAM_TIP}")

  open_issue "Upstream Zammad ${UPSTREAM_TIP_BUILD} is available" "$(cat <<BODY
Upstream \`${UPSTREAM_BRANCH}\` moved from ${UPSTREAM_BASE_BUILD} to **${UPSTREAM_TIP_BUILD}** ([compare](https://github.com/zammad/zammad/compare/${UPSTREAM_BASE}...${UPSTREAM_TIP})). \`${IMAGE}\` is still built on ${UPSTREAM_BASE_BUILD}.

Trial rebase of \`benner/${RELEASE_LINE}\`: ${trial}
${markers:+
Upstream now contains:
${markers}
}
### Update the Benner image

1. In a Zammad checkout of \`benner/${RELEASE_LINE}\` with a working \`bundle exec rails\`, run \`.github/benner/rebase-onto-upstream.sh\`.
2. Run \`.github/benner/specs.sh\`, then \`git push --force-with-lease origin benner/${RELEASE_LINE}\`.
3. The \`benner-image\` workflow publishes \`${IMAGE}:${UPSTREAM_TIP_BUILD}-bm1\`.
4. Take backups, then bump the image in gitops (runbook §5.2).

### Upstream commits

\`\`\`
${log}
\`\`\`
BODY
)"
fi

stable_line=$(echo "$STABLE_TIP_BUILD" | cut -d. -f1-2)
if [ "$stable_line" != "$RELEASE_LINE" ]; then
  markers=$(upstream_markers refs/remotes/upstream/stable)

  open_issue "Zammad ${stable_line} is released" "$(cat <<BODY
Upstream \`stable\` is now on the ${stable_line} line (${STABLE_TIP_BUILD}). The Benner build follows \`${UPSTREAM_BRANCH}\` for ${RELEASE_LINE}.
${markers:+
Upstream \`stable\` contains:
${markers}
}
Decide whether production returns to the official image (once a release contains both Benner features) or the Benner build moves to ${stable_line}.
BODY
)"
fi
