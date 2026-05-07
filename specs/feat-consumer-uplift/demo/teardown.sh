#!/usr/bin/env bash
# teardown.sh — Clean up demo environment
#
# What this does:
#   1. Destroys infrastructure in the TFC workspace (if any)
#   2. Deletes the TFC workspace
#   3. Closes any open PRs from demo triggers
#   4. Deletes demo branches
#   5. Removes consumer .tf files from repo root
#
# Usage: bash specs/feat-consumer-uplift/demo/teardown.sh [--force]

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
  error "demo.env not found."
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_NAME="$(basename "$REPO_ROOT")"
BASE_BRANCH="${BASE_BRANCH:-$(cd "$REPO_ROOT" && git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}' || echo "main")}"
TFE_ORG="${TFE_ORG:?}"
TFE_HOSTNAME="${TFE_HOSTNAME:-app.terraform.io}"
TFE_WORKSPACE="${TFE_WORKSPACE:-${REPO_NAME}}"

if [[ -z "${GITHUB_REPO:-}" ]]; then
  GITHUB_REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
fi

# ─── Confirmation ────────────────────────────────────────────────────────────
header "Teardown Configuration"
printf "    ${C_DIM}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "TFC Workspace" "${TFE_ORG}/${TFE_WORKSPACE}"
printf "    ${C_DIM}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "GitHub Repo" "$GITHUB_REPO"
echo ""

if [[ "$FORCE" != true ]]; then
  printf "  ${C_YELLOW}This will destroy the workspace and all infrastructure.${C_RESET}\n"
  printf "  ${C_WHITE}Continue? (y/N)${C_RESET} "
  read -r confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    info "Cancelled."
    exit 0
  fi
fi

# ─── Close open demo PRs ────────────────────────────────────────────────────
header "Closing Demo PRs"

if [[ -n "$GITHUB_REPO" ]]; then
  OPEN_PRS=$(gh pr list --repo "$GITHUB_REPO" --state open --json number,headRefName \
    --jq '.[] | select(.headRefName | startswith("dependabot/terraform/")) | .number' 2>/dev/null || echo "")

  if [[ -n "$OPEN_PRS" ]]; then
    while IFS= read -r pr_num; do
      gh pr close "$pr_num" --repo "$GITHUB_REPO" --delete-branch 2>/dev/null && \
        success "Closed PR #${pr_num}" || \
        warn "Could not close PR #${pr_num}"
    done <<< "$OPEN_PRS"
  else
    info "No open demo PRs found"
  fi
fi

# ─── Delete demo branches ───────────────────────────────────────────────────
header "Cleaning Up Branches"

cd "$REPO_ROOT"

# Remote branches
REMOTE_BRANCHES=$(git branch -r 2>/dev/null | grep 'origin/dependabot/terraform/' | sed 's|origin/||' || echo "")
if [[ -n "$REMOTE_BRANCHES" ]]; then
  while IFS= read -r branch; do
    branch=$(echo "$branch" | xargs)  # trim whitespace
    git push origin --delete "$branch" 2>/dev/null && \
      success "Deleted remote: ${branch}" || \
      warn "Could not delete remote: ${branch}"
  done <<< "$REMOTE_BRANCHES"
else
  info "No remote demo branches"
fi

# Local branches
LOCAL_BRANCHES=$(git branch 2>/dev/null | grep 'dependabot/terraform/' | sed 's/^[* ]*//' || echo "")
if [[ -n "$LOCAL_BRANCHES" ]]; then
  while IFS= read -r branch; do
    branch=$(echo "$branch" | xargs)
    git branch -D "$branch" 2>/dev/null && \
      success "Deleted local: ${branch}" || \
      warn "Could not delete local: ${branch}"
  done <<< "$LOCAL_BRANCHES"
fi

# ─── Destroy workspace infrastructure ───────────────────────────────────────
header "Destroying TFC Workspace"

if [[ -z "${TFE_TOKEN:-}" ]]; then
  warn "TFE_TOKEN not set — skipping workspace deletion"
else
  # Check if workspace exists
  WS_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TFE_TOKEN}" \
    "https://${TFE_HOSTNAME}/api/v2/organizations/${TFE_ORG}/workspaces/${TFE_WORKSPACE}")

  if [[ "$WS_CHECK" == "200" ]]; then
    # Get workspace ID
    WS_ID=$(curl -s \
      -H "Authorization: Bearer ${TFE_TOKEN}" \
      "https://${TFE_HOSTNAME}/api/v2/organizations/${TFE_ORG}/workspaces/${TFE_WORKSPACE}" \
      | jq -r '.data.id')

    # Check for managed resources
    RESOURCE_COUNT=$(curl -s \
      -H "Authorization: Bearer ${TFE_TOKEN}" \
      "https://${TFE_HOSTNAME}/api/v2/workspaces/${WS_ID}" \
      | jq -r '.data.attributes["resource-count"] // 0')

    if [[ "$RESOURCE_COUNT" -gt 0 ]]; then
      info "Workspace has ${RESOURCE_COUNT} managed resource(s)"
      info "Creating destroy run..."

      DESTROY_PAYLOAD=$(jq -n \
        --arg ws_id "$WS_ID" \
        '{
          data: {
            type: "runs",
            attributes: {
              "is-destroy": true,
              message: "Demo teardown — destroying all resources"
            },
            relationships: {
              workspace: {
                data: {
                  type: "workspaces",
                  id: $ws_id
                }
              }
            }
          }
        }')

      RUN_RESULT=$(curl -s \
        -X POST \
        -H "Authorization: Bearer ${TFE_TOKEN}" \
        -H "Content-Type: application/vnd.api+json" \
        -d "$DESTROY_PAYLOAD" \
        "https://${TFE_HOSTNAME}/api/v2/runs")

      RUN_ID=$(echo "$RUN_RESULT" | jq -r '.data.id // empty')

      if [[ -n "$RUN_ID" ]]; then
        success "Destroy run created: ${RUN_ID}"
        info "Waiting for destroy to complete..."

        # Poll for completion (max 5 minutes)
        for i in $(seq 1 60); do
          STATUS=$(curl -s \
            -H "Authorization: Bearer ${TFE_TOKEN}" \
            "https://${TFE_HOSTNAME}/api/v2/runs/${RUN_ID}" \
            | jq -r '.data.attributes.status')

          case "$STATUS" in
            applied)
              success "Destroy complete"
              break
              ;;
            errored|canceled|discarded|force_canceled)
              error "Destroy run ended with status: ${STATUS}"
              warn "Manual cleanup may be needed"
              break
              ;;
            confirmed|planned_and_finished)
              # Auto-apply might handle it; for destroy plans that need confirmation:
              if [[ "$STATUS" == "planned_and_finished" ]]; then
                success "Destroy complete (no resources to destroy)"
                break
              fi
              ;;
            *)
              printf "\r  ${C_DIM}  Status: %-30s${C_RESET}" "$STATUS"
              sleep 5
              ;;
          esac
        done
        echo ""
      else
        error "Failed to create destroy run"
        echo "$RUN_RESULT" | jq '.errors' 2>/dev/null || true
      fi
    else
      info "No managed resources in workspace"
    fi

    # Delete the workspace
    info "Deleting workspace..."
    DELETE_RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
      -X DELETE \
      -H "Authorization: Bearer ${TFE_TOKEN}" \
      -H "Content-Type: application/vnd.api+json" \
      "https://${TFE_HOSTNAME}/api/v2/organizations/${TFE_ORG}/workspaces/${TFE_WORKSPACE}")

    if [[ "$DELETE_RESULT" == "204" || "$DELETE_RESULT" == "200" ]]; then
      success "Workspace deleted: ${TFE_WORKSPACE}"
    else
      error "Failed to delete workspace (HTTP ${DELETE_RESULT})"
      warn "You may need to force-delete via TFC UI if resources remain"
    fi
  else
    info "Workspace '${TFE_WORKSPACE}' does not exist (HTTP ${WS_CHECK})"
  fi
fi

# ─── Clean up source repo demo branches ──────────────────────────────────────
header "Cleaning Up Source Repo"

MODULE_SOURCE_REPO="${MODULE_SOURCE_REPO:-hashi-demo-lab/terraform-aws-s3-bucket}"

# Delete any leftover demo branches on the source repo
DEMO_BRANCHES=$(gh api "repos/${MODULE_SOURCE_REPO}/git/matching-refs/heads/demo/" \
  --jq '.[].ref | sub("refs/heads/"; "")' 2>/dev/null || echo "")

if [[ -n "$DEMO_BRANCHES" ]]; then
  while IFS= read -r branch; do
    if gh api "repos/${MODULE_SOURCE_REPO}/git/refs/heads/${branch}" --method DELETE &>/dev/null; then
      success "Deleted source repo branch: ${branch}"
    else
      warn "Could not delete source repo branch: ${branch}"
    fi
  done <<< "$DEMO_BRANCHES"
else
  info "No demo branches on ${MODULE_SOURCE_REPO}"
fi

# Note: We don't delete the published PMR version because it was published
# via the source repo's CI pipeline (a real merge to main). The version
# is a legitimate release. If cleanup is needed, do it via the TFC UI.

# ─── Clean up local .tf files ───────────────────────────────────────────────
header "Cleaning Local Files"

cd "$REPO_ROOT"

# Ensure we're on the base branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
  info "Switching to ${BASE_BRANCH}..."
  git checkout "$BASE_BRANCH"
  git pull origin "$BASE_BRANCH"
fi

TF_FILES_REMOVED=false
for f in main.tf variables.tf outputs.tf versions.tf; do
  if [[ -f "$f" ]]; then
    rm "$f"
    success "Removed ${f}"
    TF_FILES_REMOVED=true
  fi
done

# Remove terraform state/cache
rm -rf .terraform .terraform.lock.hcl 2>/dev/null && info "Removed .terraform cache" || true

# Commit and push the cleanup
if [[ "$TF_FILES_REMOVED" == true ]]; then
  git add -A main.tf variables.tf outputs.tf versions.tf 2>/dev/null || true
  if ! git diff --cached --quiet; then
    git commit -m "chore: remove consumer code after demo teardown"
    git push origin "$BASE_BRANCH"
    success "Cleanup committed and pushed to ${BASE_BRANCH}"
  fi
fi

header "Teardown Complete"
echo ""
