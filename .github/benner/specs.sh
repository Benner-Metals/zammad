#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Runs the specs covering the Benner commits: every non-system spec they touch plus the
#   Microsoft, IMAP and XOAUTH2 specs around them. Examples that need live services or
#   credentials are excluded, as in upstream CI.
#
# Set BENNER_UPSTREAM_BASE to skip looking up the upstream base commit.

set -o errexit
set -o nounset
set -o pipefail

cd "$(git rev-parse --show-toplevel)"

base=${BENNER_UPSTREAM_BASE:-}
if [ -z "$base" ]; then
  base=$(.github/benner/upstream-state.sh | sed -n 's/^upstream_base=//p')
fi

mapfile -t specs < <(
  {
    git diff --name-only --diff-filter=d "${base}..HEAD" -- ':(glob)spec/**/*_spec.rb'
    find spec -name '*_spec.rb' | grep -iE 'microsoft|office365|imap|xoauth'
  } | grep -v '^spec/system/' | sort -u
)

echo "Running ${#specs[@]} spec files."
bundle exec rspec -t ~searchindex -t ~integration -t ~required_envs "${specs[@]}"
