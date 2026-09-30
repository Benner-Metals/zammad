#!/usr/bin/env bash
# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/
#
# Reserves the next image tag for HEAD by pushing the git tag benner/<image tag>, and prints
#   image_tag=<image tag>. Pushing an existing tag is rejected, so two builds can never use the
#   same number; after a rejection the script refetches the tags and tries the next number.
#
# Usage: reserve-tag.sh <upstream build> <upstream base commit>

set -o errexit
set -o nounset
set -o pipefail

build=$1
base=$2

for _attempt in 1 2 3 4 5; do
  tag=$(.github/benner/image-tag.sh "$build" | sed -n 's/^next_tag=//p')

  git tag -a "benner/${tag}" \
    -m "ghcr.io/benner-metals/zammad:${tag}" \
    -m "Upstream base: ${base} (${build})"

  if git push --quiet origin "refs/tags/benner/${tag}"; then
    echo "image_tag=${tag}"
    exit 0
  fi

  git tag --delete "benner/${tag}" > /dev/null
  git fetch --quiet origin 'refs/tags/benner/*:refs/tags/benner/*'
done

echo 'Could not reserve an image tag.' >&2
exit 1
