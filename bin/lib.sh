#!/usr/bin/env bash
# Shared library for claude-pm scripts. Source this, don't execute it.
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

detect_repo() {
  local remote_url
  if [ -d ".jj" ]; then
    remote_url=$(jj git remote list 2>/dev/null | head -1 | awk '{print $2}')
  elif [ -d "../.jj" ]; then
    remote_url=$(cd .. && jj git remote list 2>/dev/null | head -1 | awk '{print $2}')
  else
    remote_url=$(git remote get-url origin 2>/dev/null)
  fi

  [ -n "$remote_url" ] || die "no git/jj remote found"

  local owner_repo
  owner_repo=$(echo "$remote_url" | sed 's|.*github\.com[:/]||;s|\.git$||')
  DETECTED_OWNER=$(echo "$owner_repo" | cut -d/ -f1)
  DETECTED_REPO=$(echo "$owner_repo" | cut -d/ -f2)
}

load_config() {
  local config_file="${HOME}/.config/claude-pm/${DETECTED_REPO}.taskboard.json"
  [ -f "$config_file" ] || die "no taskboard configured for ${DETECTED_REPO}. Run /task setup first."

  PROJECT_NUMBER=$(jq -r '.project_number' "$config_file")
  OWNER=$(jq -r '.owner' "$config_file")
  OWNER_TYPE=$(jq -r '.owner_type' "$config_file")
  REPO=$(jq -r '.repo' "$config_file")
  PROJECT_ID=$(jq -r '.project_id' "$config_file")
  STATUS_FIELD_ID=$(jq -r '.field_ids.status' "$config_file")
  PLAN_FIELD_ID=$(jq -r '.field_ids.plan' "$config_file")

  # Load status option IDs as STATUS_OPT_<Name>
  STATUS_OPT_Idea=$(jq -r '.status_option_ids.Idea' "$config_file")
  STATUS_OPT_Define=$(jq -r '.status_option_ids.Define' "$config_file")
  STATUS_OPT_Design=$(jq -r '.status_option_ids.Design' "$config_file")
  STATUS_OPT_Plan=$(jq -r '.status_option_ids.Plan' "$config_file")
  STATUS_OPT_Implement=$(jq -r '.status_option_ids.Implement' "$config_file")
  STATUS_OPT_Verify=$(jq -r '.status_option_ids.Verify' "$config_file")
  STATUS_OPT_Ship=$(jq -r '.status_option_ids.Ship' "$config_file")
  STATUS_OPT_Done=$(jq -r '.status_option_ids.Done' "$config_file")
}

require_config() {
  detect_repo
  load_config
}

# Resolve a human-readable status name to its option ID
status_option_id() {
  local name="$1"
  local var="STATUS_OPT_${name}"
  local id="${!var:-}"
  [ -n "$id" ] || die "unknown status: ${name}"
  echo "$id"
}
