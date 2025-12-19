#!/usr/bin/env bash
set -euo pipefail

# Calculate cutoff timestamp (2 hours ago)
cutoff=$(date -u -d '2 hours ago' +%s)
echo "Cutoff timestamp: $cutoff ($(date -u -d @$cutoff))"

echo "::group::Cleaning up servers"
hcloud server list -o json | jq -c '.[]' | while read -r server; do
  id=$(echo "$server" | jq -r '.id')
  name=$(echo "$server" | jq -r '.name')
  created=$(echo "$server" | jq -r '.created')
  created_ts=$(date -u -d "$created" +%s)

  if [[ "$created_ts" -lt "$cutoff" ]]; then
    echo "Deleting server $name (id=$id, created=$created)"
    hcloud server delete "$id" || true
  else
    echo "Keeping server $name (id=$id, created=$created) - not old enough"
  fi
done

echo "::endgroup::"

echo "::group::Cleaning up SSH keys"
hcloud ssh-key list -o json | jq -c '.[]' | while read -r key; do
  id=$(echo "$key" | jq -r '.id')
  name=$(echo "$key" | jq -r '.name')
  created=$(echo "$key" | jq -r '.created')
  created_ts=$(date -u -d "$created" +%s)

  if [[ "$name" == hcloud-upload-image-* ]] || [[ "$name" == smoke-test-* ]]; then
    if [[ "$created_ts" -lt "$cutoff" ]]; then
      echo "Deleting SSH key $name (id=$id, created=$created)"
      hcloud ssh-key delete "$id" || true
    else
      echo "Keeping SSH key $name (id=$id, created=$created) - not old enough"
    fi
  fi
done

echo "::endgroup::"

echo "::group::Cleaning up snapshots"

# Find the newest nixos-hetzner-demo- snapshot to preserve
newest_demo_id=$(hcloud image list -t snapshot -o json |
  jq -r '[.[] | select(.name != null) | select(.name | startswith("nixos-hetzner-demo-"))] | sort_by(.created) | last | .id // ""')

if [[ -n "$newest_demo_id" ]]; then
  echo "Preserving newest nixos-hetzner-demo- snapshot: id=$newest_demo_id"
fi

hcloud image list -t snapshot -o json | jq -c '.[]' | while read -r img; do
  id=$(echo "$img" | jq -r '.id')
  name=$(echo "$img" | jq -r '.name // ""')
  created=$(echo "$img" | jq -r '.created')
  created_ts=$(date -u -d "$created" +%s)

  if [[ "$name" == smoke-test-* ]]; then
    if [[ "$created_ts" -lt "$cutoff" ]]; then
      echo "Deleting snapshot $name (id=$id, created=$created)"
      hcloud image delete "$id" || true
    else
      echo "Keeping snapshot $name (id=$id, created=$created) - not old enough"
    fi
  elif [[ "$name" == nixos-hetzner-demo-* ]]; then
    if [[ "$id" == "$newest_demo_id" ]]; then
      echo "Preserving newest nixos-hetzner-demo- snapshot $name (id=$id, created=$created)"
    elif [[ "$created_ts" -lt "$cutoff" ]]; then
      echo "Deleting snapshot $name (id=$id, created=$created)"
      hcloud image delete "$id" || true
    else
      echo "Keeping snapshot $name (id=$id, created=$created) - not old enough"
    fi
  fi
done

echo "::endgroup::"
echo "Cleanup complete"
