#!/usr/bin/env bash

set -e

# Function to run repo sync until successful
function repo_sync_until_success() {
  # disable exit on error - we expect this to fail a few times
  set +e

  # perform sync
  # (using -j4 makes the sync less likely to hit rate limiting)
  until repo sync -c -j4 --fail-fast --no-clone-bundle --no-tags; do
    echo "repo sync failed, retrying in 1 minute..."
    sleep 60
  done

  # re-enable exit on error - we're done failing now! :)
  set -e
}