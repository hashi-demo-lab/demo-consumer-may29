#!/usr/bin/env bash
# setup.sh — Automated demo environment setup for Consumer Module Uplift
#
# What this does:
#   1. Loads configuration from demo.env
#   2. Sets the repo default branch to BASE_BRANCH (required for claude-code-action)
#   3. Creates an HCP Terraform workspace (CLI-driven) in the sandbox project
#   4. Templates consumer Terraform code with org/workspace/module values
#   5. Creates GitHub labels for the pipeline
#   6. Commits consumer code to the demo repo's base branch
#   7. Prints next steps (publish + trigger)
#
# Prerequisites:
#   - gh CLI authenticated
#   - TFE_TOKEN environment variable set
#   - Demo repo already created (via create-demo-repos.zsh) and cloned
#   - Run from the root of the demo repo
#
# Usage: bash specs/feat-consumer-uplift/demo/setup.sh

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
  error "demo.env not found. Copy the example and fill in values:"
  echo "    cp ${SCRIPT_DIR}/demo.env.example ${SCRIPT_DIR}/demo.env"
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

# ─── Derive defaults ────────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_NAME="$(basename "$REPO_ROOT")"

TFE_ORG="${TFE_ORG:?TFE_ORG is required}"
TFE_PROJECT="${TFE_PROJECT:-sandbox}"
TFE_HOSTNAME="${TFE_HOSTNAME:-app.terraform.io}"
BASE_BRANCH="${BASE_BRANCH:-$(cd "$REPO_ROOT" && git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}' || echo "main")}"
MODULE_SOURCE="${MODULE_SOURCE:?MODULE_SOURCE is required}"
MODULE_CURRENT_VERSION="${MODULE_CURRENT_VERSION:?MODULE_CURRENT_VERSION is required}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"

# Detect GitHub repo from remote
if [[ -z "${GITHUB_REPO:-}" ]]; then
  GITHUB_REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
fi

if [[ -z "$GITHUB_REPO" ]]; then
  error "Could not detect GitHub repo. Set GITHUB_REPO in demo.env"
  exit 1
fi

# Default workspace name from repo name (prefer GITHUB_REPO over local dir)
TFE_WORKSPACE="${TFE_WORKSPACE:-$(basename "$GITHUB_REPO")}"

# ─── Display config ─────────────────────────────────────────────────────────
header "Demo Setup Configuration"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "TFC Org" "$TFE_ORG"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "TFC Project" "$TFE_PROJECT"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "TFC Workspace" "$TFE_WORKSPACE"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "GitHub Repo" "$GITHUB_REPO"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Module" "$MODULE_SOURCE"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Version" "$MODULE_CURRENT_VERSION"
printf "    ${C_DIM}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "AWS Region" "$AWS_REGION"
echo ""

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

if ! gh auth token &>/dev/null 2>&1; then
  error "Not authenticated to GitHub. Run: gh auth login (or set GITHUB_TOKEN)"
  exit 1
fi
success "GitHub authenticated"

# ─── Ensure on base branch ─────────────────────────────────────────────────
cd "$REPO_ROOT"
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
  error "Not on base branch (currently on '${CURRENT_BRANCH}', expected '${BASE_BRANCH}')"
  info "Run: git checkout ${BASE_BRANCH}"
  exit 1
fi
git pull origin "$BASE_BRANCH"
success "On ${BASE_BRANCH} (up to date)"

# ─── Set default branch (early — required for claude-code-action & PRs) ────
header "Default Branch"

DEFAULT_BRANCH=$(gh api "repos/${GITHUB_REPO}" --jq '.default_branch' 2>/dev/null || echo "")
if [[ "$DEFAULT_BRANCH" == "$BASE_BRANCH" ]]; then
  success "Default branch already set to ${BASE_BRANCH}"
else
  info "Setting default branch to ${BASE_BRANCH} (required for claude-code-action)..."
  if gh repo edit "$GITHUB_REPO" --default-branch "$BASE_BRANCH" 2>/dev/null; then
    success "Default branch set to ${BASE_BRANCH}"
  else
    warn "Failed to set default branch — set it manually:"
    printf "     ${C_DIM}gh repo edit %s --default-branch %s${C_RESET}\n" "$GITHUB_REPO" "$BASE_BRANCH"
  fi
fi

# ─── Resolve project ID ─────────────────────────────────────────────────────
header "Resolving TFC Project"

PROJECT_ID=$(curl -s \
  -H "Authorization: Bearer ${TFE_TOKEN}" \
  -H "Content-Type: application/vnd.api+json" \
  "https://${TFE_HOSTNAME}/api/v2/organizations/${TFE_ORG}/projects?q=${TFE_PROJECT}" \
  | jq -r ".data[] | select(.attributes.name == \"${TFE_PROJECT}\") | .id")

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  error "Project '${TFE_PROJECT}' not found in org '${TFE_ORG}'"
  exit 1
fi
success "Project found: ${TFE_PROJECT} (${PROJECT_ID})"

# ─── Create workspace ───────────────────────────────────────────────────────
header "Creating TFC Workspace"

# Check if workspace already exists
EXISTING_WS=$(curl -s \
  -H "Authorization: Bearer ${TFE_TOKEN}" \
  -H "Content-Type: application/vnd.api+json" \
  "https://${TFE_HOSTNAME}/api/v2/organizations/${TFE_ORG}/workspaces/${TFE_WORKSPACE}" \
  | jq -r '.data.id // empty')

if [[ -n "$EXISTING_WS" ]]; then
  warn "Workspace '${TFE_WORKSPACE}' already exists (${EXISTING_WS})"
  info "Skipping workspace creation"
else
  PAYLOAD=$(jq -n \
    --arg name "$TFE_WORKSPACE" \
    --arg project_id "$PROJECT_ID" \
    '{
      data: {
        type: "workspaces",
        attributes: {
          name: $name,
          "execution-mode": "remote",
          "auto-apply": false,
          "terraform-version": "~> 1.11.0"
        },
        relationships: {
          project: {
            data: {
              type: "projects",
              id: $project_id
            }
          }
        }
      }
    }')

  CREATE_RESULT=$(curl -s \
    -X POST \
    -H "Authorization: Bearer ${TFE_TOKEN}" \
    -H "Content-Type: application/vnd.api+json" \
    -d "$PAYLOAD" \
    "https://${TFE_HOSTNAME}/api/v2/organizations/${TFE_ORG}/workspaces")

  WS_ID=$(echo "$CREATE_RESULT" | jq -r '.data.id // empty')
  if [[ -z "$WS_ID" ]]; then
    error "Failed to create workspace:"
    echo "$CREATE_RESULT" | jq '.errors' 2>/dev/null || echo "$CREATE_RESULT"
    exit 1
  fi
  success "Workspace created: ${TFE_WORKSPACE} (${WS_ID})"
fi

# ─── Template consumer code ─────────────────────────────────────────────────
header "Templating Consumer Code"

CONSUMER_SRC="${SCRIPT_DIR}/consumer-code"
CONSUMER_DEST="${REPO_ROOT}"

# Copy and template each .tf.tpl file → .tf
for tpl_file in "${CONSUMER_SRC}"/*.tf.tpl; do
  filename=$(basename "${tpl_file%.tpl}")
  info "Templating ${filename}"
  sed \
    -e "s|__TFE_ORG__|${TFE_ORG}|g" \
    -e "s|__TFE_HOSTNAME__|${TFE_HOSTNAME}|g" \
    -e "s|__TFE_PROJECT__|${TFE_PROJECT}|g" \
    -e "s|__TFE_WORKSPACE__|${TFE_WORKSPACE}|g" \
    -e "s|__MODULE_SOURCE__|${MODULE_SOURCE}|g" \
    -e "s|__MODULE_VERSION__|${MODULE_CURRENT_VERSION}|g" \
    -e "s|__AWS_REGION__|${AWS_REGION}|g" \
    "$tpl_file" > "${CONSUMER_DEST}/${filename}"
done

success "Consumer code templated to repo root"

# ─── Create GitHub labels ───────────────────────────────────────────────────
header "Creating GitHub Labels"

declare -A LABELS=(
  ["risk:low"]="0E8A16"
  ["risk:medium"]="FBCA04"
  ["risk:high"]="E99695"
  ["risk:critical"]="D93F0B"
  ["auto-merge"]="0E8A16"
  ["needs-review"]="FBCA04"
  ["needs-revalidation"]="1D76DB"
  ["breaking-change"]="D93F0B"
  ["version:patch"]="C2E0C6"
  ["version:minor"]="BFD4F2"
  ["version:major"]="F9D0C4"
  ["dependencies"]="0366D6"
  ["terraform"]="7B42BC"
  ["incident:apply-failure"]="B60205"
  ["rollback"]="D93F0B"
  ["priority:high"]="D93F0B"
)

for label in "${!LABELS[@]}"; do
  color="${LABELS[$label]}"
  if gh label create "$label" --color "$color" --repo "$GITHUB_REPO" 2>/dev/null; then
    success "Created label: ${label}"
  else
    info "Label exists: ${label}"
  fi
done

# ─── Commit and push ────────────────────────────────────────────────────────
header "Committing Consumer Code"

cd "$REPO_ROOT"

# Stage the consumer .tf files
git add versions.tf variables.tf main.tf outputs.tf 2>/dev/null || true

if git diff --cached --quiet; then
  warn "No changes to commit (consumer code may already exist)"
else
  git commit -m "feat: add consumer code for module uplift demo

Configures S3 bucket consumer using ${MODULE_SOURCE}@${MODULE_CURRENT_VERSION}
with HCP Terraform backend (workspace: ${TFE_WORKSPACE})."

  info "Pushing to origin/${BASE_BRANCH}..."
  git push origin "$BASE_BRANCH"
  success "Consumer code pushed to ${BASE_BRANCH}"
fi

# ─── Print next steps ───────────────────────────────────────────────────────
header "Setup Complete"

echo ""
printf "  ${C_WHITE}Next steps:${C_RESET}\n\n"
STEP=1
printf "  ${C_CYAN}${STEP}.${C_RESET} Publish a new module version to the PMR:\n"
printf "     ${C_DIM}bash specs/feat-consumer-uplift/demo/publish-module-version.sh${C_RESET}\n"
STEP=$((STEP + 1))
printf "  ${C_CYAN}${STEP}.${C_RESET} Trigger the demo:\n"
printf "     ${C_DIM}bash specs/feat-consumer-uplift/demo/trigger-bump.sh${C_RESET}\n"
echo ""
