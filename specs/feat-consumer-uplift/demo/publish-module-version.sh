#!/usr/bin/env bash
# publish-module-version.sh — Publish a new PMR version by driving the source repo's CI pipeline
#
# What this does:
#   1. Queries PMR for the current latest version
#   2. Calculates the expected next version (current + bump type)
#   3. Creates a branch + trivial commit on the source module repo
#   4. Opens a PR with the correct semver label (semver:patch/minor/major)
#   5. Waits for validation checks, then merges the PR
#   6. Waits for the pr_merge.yml workflow to publish to the PMR
#   7. Polls the PMR until the new version is available
#   8. Updates MODULE_TARGET_VERSION in demo.env
#
# The source repo (e.g. hashi-demo-lab/terraform-aws-s3-bucket) has:
#   - module_validate.yml: runs on PR (requires semver label, validates .tf changes)
#   - pr_merge.yml: runs on merge to main → publishes to TFC PMR via API
#
# Prerequisites:
#   - gh CLI authenticated (needs write access to the source module repo)
#   - TFE_TOKEN environment variable set (to query PMR for current version)
#   - demo.env configured
#
# Usage:
#   bash specs/feat-consumer-uplift/demo/publish-module-version.sh [--bump patch|minor|major]
#
# Default bump type is "patch".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Color helpers ───────────────────────────────────────────────────────────
C_CYAN="\033[38;2;80;220;235m"
C_GREEN="\033[38;2;80;250;160m"
C_RED="\033[38;2;255;85;85m"
C_YELLOW="\033[38;2;255;200;80m"
C_WHITE="\033[1;37m"
C_DIM="\033[38;5;243m"
C_RESET="\033[0m"

info()    { printf "  ${C_CYAN}▸${C_RESET} %s\n" "$1"; }
success() { printf "  ${C_GREEN}✔${C_RESET} %s\n" "$1"; }
error()   { printf "  ${C_RED}✖${C_RESET} %s\n" "$1"; }
warn()    { printf "  ${C_YELLOW}▲${C_RESET} %s\n" "$1"; }
header()  { printf "\n  ${C_CYAN}▎${C_RESET} ${C_WHITE}%s${C_RESET}\n\n" "$1"; }

# ─── Load config ─────────────────────────────────────────────────────────────
ENV_FILE="${SCRIPT_DIR}/demo.env"
if [[ ! -f "$ENV_FILE" ]]; then
  error "demo.env not found. Run setup.sh first."
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

# ─── Parse args ──────────────────────────────────────────────────────────────
BUMP_TYPE="patch"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump) BUMP_TYPE="$2"; shift 2 ;;
    *) error "Unknown arg: $1"; exit 1 ;;
  esac
done

# Validate bump type
case "$BUMP_TYPE" in
  patch|minor|major) ;;
  *) error "Invalid bump type: ${BUMP_TYPE}. Must be patch, minor, or major."; exit 1 ;;
esac

TFE_HOSTNAME="${TFE_HOSTNAME:-app.terraform.io}"
TFE_ORG="${TFE_ORG:?TFE_ORG is required}"
MODULE_NAME="${MODULE_NAME:-s3-bucket}"
MODULE_PROVIDER="${MODULE_PROVIDER:-aws}"
MODULE_SOURCE_REPO="${MODULE_SOURCE_REPO:-hashi-demo-lab/terraform-aws-s3-bucket}"
MODULE_SOURCE_BRANCH="${MODULE_SOURCE_BRANCH:-master}"

# ─── Pre-flight checks ──────────────────────────────────────────────────────
header "Pre-flight Checks"

if [[ -z "${TFE_TOKEN:-}" ]]; then
  error "TFE_TOKEN environment variable is not set"
  exit 1
fi
success "TFE_TOKEN set"

if ! command -v gh &>/dev/null; then
  error "GitHub CLI (gh) is not installed"
  exit 1
fi
success "GitHub CLI available"

if ! command -v jq &>/dev/null; then
  error "jq is not installed"
  exit 1
fi
success "jq available"

# Check write access to source repo
if ! gh api "repos/${MODULE_SOURCE_REPO}" --jq '.permissions.push' 2>/dev/null | grep -q 'true'; then
  error "No push access to ${MODULE_SOURCE_REPO}"
  info "You need write access to create branches and merge PRs"
  exit 1
fi
success "Push access to ${MODULE_SOURCE_REPO}"

# ─── Query current version from PMR ─────────────────────────────────────────
header "Resolving Current Version"

# Use the same Registry v1 API that the source repo's get_module_version.py uses
PMR_LIST_URL="https://${TFE_HOSTNAME}/api/registry/v1/modules/${TFE_ORG}/${MODULE_NAME}/${MODULE_PROVIDER}/"
PMR_RESPONSE=$(curl -s \
  -H "Authorization: Bearer ${TFE_TOKEN}" \
  "${PMR_LIST_URL}")

CURRENT_VERSION=$(echo "$PMR_RESPONSE" | jq -r '
  [.versions[] | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] |
  sort_by(split(".") | map(tonumber)) |
  last // "0.0.0"
')

if [[ -z "$CURRENT_VERSION" || "$CURRENT_VERSION" == "null" ]]; then
  error "Could not determine current version from PMR"
  info "Response: $(echo "$PMR_RESPONSE" | jq -c '.' 2>/dev/null || echo "$PMR_RESPONSE")"
  exit 1
fi

success "Current PMR version: ${CURRENT_VERSION}"

# ─── Calculate expected next version ─────────────────────────────────────────
IFS='.' read -r major minor patch_num <<< "$CURRENT_VERSION"
case "$BUMP_TYPE" in
  patch) NEW_VERSION="${major}.${minor}.$((patch_num + 1))" ;;
  minor) NEW_VERSION="${major}.$((minor + 1)).0" ;;
  major) NEW_VERSION="$((major + 1)).0.0" ;;
esac

# ─── Display config ──────────────────────────────────────────────────────────
header "Publish Module Version"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Source Repo" "$MODULE_SOURCE_REPO"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Base Branch" "$MODULE_SOURCE_BRANCH"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Bump Type" "$BUMP_TYPE"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Current Version" "$CURRENT_VERSION"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Expected Version" "$NEW_VERSION"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Publishing via" "Source repo CI (pr_merge.yml)"
echo ""

# ─── Helper: check version status via module-level API ───────────────────────
# The v2 versioned endpoint (/.../{version}) returns 404 for branch-based modules.
# Instead, query the module-level endpoint and inspect version-statuses array.
PMR_MODULE_URL="https://${TFE_HOSTNAME}/api/v2/organizations/${TFE_ORG}/registry-modules/private/${TFE_ORG}/${MODULE_NAME}/${MODULE_PROVIDER}"

get_version_status() {
  local ver="$1"
  curl -s \
    -H "Authorization: Bearer ${TFE_TOKEN}" \
    "${PMR_MODULE_URL}" | jq -r --arg v "$ver" '
      .data.attributes["version-statuses"][] |
      select(.version == $v) | .status
    ' 2>/dev/null || echo ""
}

# ─── Check if version already exists ─────────────────────────────────────────
EXISTING_STATUS=$(get_version_status "$NEW_VERSION")

if [[ "$EXISTING_STATUS" == "ok" ]]; then
  warn "Version ${NEW_VERSION} already exists in PMR (status: ok)"
  info "Skipping publish — updating demo.env and continuing"

  if grep -q "^MODULE_TARGET_VERSION=" "$ENV_FILE"; then
    sed -i "s|^MODULE_TARGET_VERSION=.*|MODULE_TARGET_VERSION=\"${NEW_VERSION}\"|" "$ENV_FILE"
  else
    echo "MODULE_TARGET_VERSION=\"${NEW_VERSION}\"" >> "$ENV_FILE"
  fi
  success "MODULE_TARGET_VERSION set to ${NEW_VERSION}"

  header "Ready"
  printf "  ${C_WHITE}Next step:${C_RESET}\n"
  printf "     ${C_DIM}bash specs/feat-consumer-uplift/demo/trigger-bump.sh${C_RESET}\n"
  echo ""
  exit 0
elif [[ -n "$EXISTING_STATUS" ]]; then
  warn "Version ${NEW_VERSION} exists but status is: ${EXISTING_STATUS}"
  info "Will attempt to re-publish..."
fi

# ─── Create branch on source repo ───────────────────────────────────────────
header "Creating Branch on Source Repo"

TIMESTAMP=$(date +%s)
DEMO_BRANCH="demo/bump-${BUMP_TYPE}-${TIMESTAMP}"

# Get the SHA of the base branch HEAD
BASE_SHA=$(gh api "repos/${MODULE_SOURCE_REPO}/git/refs/heads/${MODULE_SOURCE_BRANCH}" \
  --jq '.object.sha' 2>/dev/null) || {
  error "Could not resolve HEAD of ${MODULE_SOURCE_REPO}@${MODULE_SOURCE_BRANCH}"
  exit 1
}
info "Base branch HEAD: ${BASE_SHA:0:12}"

# Create the branch
gh api "repos/${MODULE_SOURCE_REPO}/git/refs" \
  --method POST \
  --field "ref=refs/heads/${DEMO_BRANCH}" \
  --field "sha=${BASE_SHA}" > /dev/null 2>&1 || {
  error "Failed to create branch ${DEMO_BRANCH}"
  exit 1
}
success "Branch created: ${DEMO_BRANCH}"

# ─── Make a trivial .tf change ──────────────────────────────────────────────
header "Committing Trivial Change"

# Get the current content of variables.tf (or any .tf file) to modify
TARGET_FILE="variables.tf"
FILE_INFO=$(gh api "repos/${MODULE_SOURCE_REPO}/contents/${TARGET_FILE}?ref=${DEMO_BRANCH}" 2>/dev/null) || {
  # Fallback to main.tf if variables.tf doesn't exist
  TARGET_FILE="main.tf"
  FILE_INFO=$(gh api "repos/${MODULE_SOURCE_REPO}/contents/${TARGET_FILE}?ref=${DEMO_BRANCH}" 2>/dev/null) || {
    error "Could not find a .tf file to modify"
    # Clean up branch
    gh api "repos/${MODULE_SOURCE_REPO}/git/refs/heads/${DEMO_BRANCH}" --method DELETE > /dev/null 2>&1 || true
    exit 1
  }
}

FILE_SHA=$(echo "$FILE_INFO" | jq -r '.sha')
FILE_CONTENT_B64=$(echo "$FILE_INFO" | jq -r '.content' | tr -d '\n')
FILE_CONTENT=$(echo "$FILE_CONTENT_B64" | base64 -d)

# Append or update a demo comment at the end of the file
DEMO_MARKER="# Demo trigger: ${BUMP_TYPE} bump at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
if echo "$FILE_CONTENT" | grep -q "^# Demo trigger:"; then
  # Replace existing demo marker
  UPDATED_CONTENT=$(echo "$FILE_CONTENT" | sed "s|^# Demo trigger:.*|${DEMO_MARKER}|")
else
  # Append demo marker
  UPDATED_CONTENT="${FILE_CONTENT}
${DEMO_MARKER}
"
fi

NEW_CONTENT_B64=$(echo -n "$UPDATED_CONTENT" | base64 -w 0)

gh api "repos/${MODULE_SOURCE_REPO}/contents/${TARGET_FILE}" \
  --method PUT \
  --field "message=chore: demo ${BUMP_TYPE} bump trigger" \
  --field "content=${NEW_CONTENT_B64}" \
  --field "sha=${FILE_SHA}" \
  --field "branch=${DEMO_BRANCH}" > /dev/null 2>&1 || {
  error "Failed to commit change to ${TARGET_FILE}"
  gh api "repos/${MODULE_SOURCE_REPO}/git/refs/heads/${DEMO_BRANCH}" --method DELETE > /dev/null 2>&1 || true
  exit 1
}
success "Committed change to ${TARGET_FILE} on ${DEMO_BRANCH}"

# ─── Create PR with semver label ─────────────────────────────────────────────
header "Creating Pull Request"

PR_TITLE="chore: demo ${BUMP_TYPE} bump (${CURRENT_VERSION} → ${NEW_VERSION})"
PR_BODY="Automated demo trigger for consumer module uplift pipeline.

Bumps module version via \`${BUMP_TYPE}\` release: \`${CURRENT_VERSION}\` → \`${NEW_VERSION}\`

_Created by \`publish-module-version.sh\` — safe to merge._"

PR_OUTPUT=$(gh pr create \
  --repo "$MODULE_SOURCE_REPO" \
  --head "$DEMO_BRANCH" \
  --base "$MODULE_SOURCE_BRANCH" \
  --title "$PR_TITLE" \
  --body "$PR_BODY" \
  --label "semver:${BUMP_TYPE}" 2>&1) || {
  error "Failed to create PR"
  echo "$PR_OUTPUT"
  gh api "repos/${MODULE_SOURCE_REPO}/git/refs/heads/${DEMO_BRANCH}" --method DELETE > /dev/null 2>&1 || true
  exit 1
}

# Extract the URL (last line containing github.com) and PR number from the output
PR_URL=$(echo "$PR_OUTPUT" | grep -oE 'https://github\.com/[^ ]+' | tail -1)
PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')

if [[ -z "$PR_NUMBER" ]]; then
  error "Could not extract PR number from output:"
  echo "$PR_OUTPUT"
  exit 1
fi
success "PR created: ${PR_URL}"

# ─── Wait for validation workflow to complete ─────────────────────────────────
header "Waiting for CI Validation"

info "Waiting for module_validate.yml to complete on ${DEMO_BRANCH}..."

# Poll workflow runs on the demo branch (gh pr checks may not see them)
CHECKS_PASSED=false
for i in $(seq 1 60); do
  # Query workflow runs for this branch
  RUN_INFO=$(gh run list \
    --repo "$MODULE_SOURCE_REPO" \
    --branch "$DEMO_BRANCH" \
    --limit 1 \
    --json status,conclusion,name 2>/dev/null || echo "[]")

  RUN_STATUS=$(echo "$RUN_INFO" | jq -r '.[0].status // "not_found"')
  RUN_CONCLUSION=$(echo "$RUN_INFO" | jq -r '.[0].conclusion // ""')
  RUN_NAME=$(echo "$RUN_INFO" | jq -r '.[0].name // ""')

  case "$RUN_STATUS" in
    completed)
      if [[ "$RUN_CONCLUSION" == "success" ]]; then
        CHECKS_PASSED=true
        echo ""
        success "CI passed: ${RUN_NAME}"
        break
      elif [[ "$RUN_CONCLUSION" == "failure" ]]; then
        echo ""
        error "CI failed: ${RUN_NAME}"
        warn "PR remains open: ${PR_URL}"
        warn "Check: https://github.com/${MODULE_SOURCE_REPO}/actions"
        warn "Fix the issue and re-run, or merge manually"
        exit 1
      else
        echo ""
        warn "CI completed with conclusion: ${RUN_CONCLUSION}"
        info "Attempting merge anyway..."
        CHECKS_PASSED=true
        break
      fi
      ;;
    in_progress|queued|waiting|pending|requested)
      printf "\r  ${C_DIM}  Status: %-20s (attempt %d/60)${C_RESET}" "$RUN_STATUS" "$i"
      sleep 10
      ;;
    not_found)
      # Workflow may not have triggered yet
      printf "\r  ${C_DIM}  Waiting for workflow to start... (attempt %d/60)${C_RESET}" "$i"
      sleep 10
      ;;
    *)
      printf "\r  ${C_DIM}  Status: %-20s (attempt %d/60)${C_RESET}" "$RUN_STATUS" "$i"
      sleep 10
      ;;
  esac
done
echo ""

if [[ "$CHECKS_PASSED" != true ]]; then
  warn "Timed out waiting for CI (10 minutes)"
  info "Attempting merge anyway — checks may not be required..."
fi

# ─── Merge the PR ────────────────────────────────────────────────────────────
header "Merging Pull Request"

MERGE_RESULT=$(gh pr merge "$PR_NUMBER" \
  --repo "$MODULE_SOURCE_REPO" \
  --squash \
  --delete-branch \
  --subject "${PR_TITLE}" 2>&1) || {
  error "Failed to merge PR:"
  echo "$MERGE_RESULT"
  warn "PR remains open: ${PR_URL}"
  warn "Merge manually, then re-run this script (it will detect the existing version)"
  exit 1
}

success "PR merged and branch deleted"

# ─── Wait for pr_merge.yml to publish ────────────────────────────────────────
header "Waiting for Release Workflow"

info "pr_merge.yml should trigger now and publish version ${NEW_VERSION}..."

# Give GitHub Actions a moment to pick up the merge event
sleep 5

# Poll using the module-level version-statuses (v2 versioned endpoint returns 404 for branch-based modules)
PUBLISH_COMPLETE=false
for i in $(seq 1 36); do
  VERSION_STATUS=$(get_version_status "$NEW_VERSION")

  case "$VERSION_STATUS" in
    ok)
      PUBLISH_COMPLETE=true
      echo ""
      success "Version ${NEW_VERSION} is available in PMR (status: ok)"
      break
      ;;
    pending|cloning|ingressing)
      printf "\r  ${C_DIM}  PMR status: %-20s (attempt %d/36)${C_RESET}" "$VERSION_STATUS" "$i"
      sleep 10
      ;;
    errored)
      echo ""
      error "PMR ingestion failed for version ${NEW_VERSION}"
      info "Check: https://${TFE_HOSTNAME}/app/${TFE_ORG}/registry/modules/private/${TFE_ORG}/${MODULE_NAME}/${MODULE_PROVIDER}"
      exit 1
      ;;
    "")
      # Version not yet visible — release workflow may still be running
      printf "\r  ${C_DIM}  Waiting for publish... (attempt %d/36)${C_RESET}" "$i"
      sleep 10
      ;;
    *)
      printf "\r  ${C_DIM}  PMR status: %-20s (attempt %d/36)${C_RESET}" "$VERSION_STATUS" "$i"
      sleep 10
      ;;
  esac
done
echo ""

if [[ "$PUBLISH_COMPLETE" != true ]]; then
  error "Timed out waiting for version ${NEW_VERSION} in PMR (6 minutes)"
  info "The PR was merged — the release workflow may still be running"
  info "Check: https://github.com/${MODULE_SOURCE_REPO}/actions"
  info "Once published, update demo.env manually: MODULE_TARGET_VERSION=\"${NEW_VERSION}\""
  exit 1
fi

# ─── Update demo.env ────────────────────────────────────────────────────────
header "Updating demo.env"

if grep -q "^MODULE_TARGET_VERSION=" "$ENV_FILE"; then
  sed -i "s|^MODULE_TARGET_VERSION=.*|MODULE_TARGET_VERSION=\"${NEW_VERSION}\"|" "$ENV_FILE"
  success "Updated MODULE_TARGET_VERSION to ${NEW_VERSION}"
else
  echo "MODULE_TARGET_VERSION=\"${NEW_VERSION}\"" >> "$ENV_FILE"
  success "Added MODULE_TARGET_VERSION=${NEW_VERSION}"
fi

# Also update MODULE_CURRENT_VERSION since the PMR baseline has moved
if grep -q "^MODULE_CURRENT_VERSION=" "$ENV_FILE"; then
  sed -i "s|^MODULE_CURRENT_VERSION=.*|MODULE_CURRENT_VERSION=\"${CURRENT_VERSION}\"|" "$ENV_FILE"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
header "Module Version Published"

echo ""
printf "  ${C_WHITE}Version ${NEW_VERSION} is live in the private registry.${C_RESET}\n"
printf "  ${C_DIM}Published via source repo CI: ${MODULE_SOURCE_REPO}${C_RESET}\n"
printf "  ${C_DIM}Bump type: ${BUMP_TYPE} (${CURRENT_VERSION} → ${NEW_VERSION})${C_RESET}\n"
echo ""
printf "  ${C_WHITE}Next step:${C_RESET}\n"
printf "     ${C_DIM}bash specs/feat-consumer-uplift/demo/trigger-bump.sh${C_RESET}\n"
echo ""
