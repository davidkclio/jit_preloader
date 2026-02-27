#!/usr/bin/env bash
# Run documentation analysis, have Claude apply the suggested doc changes, then
# create a branch and open a PR (same as workflow with create_pr=true, but local).
#
# Prereqs: npm install -g @anthropic-ai/claude-code; gh CLI; push access to origin.
# Usage: ANTHROPIC_API_KEY=your-key script/ci/create_dev_documentation_pr.sh
#
# Runs from current branch. Pushes branch dev-docs/-<current-branch>
# and opens a PR into the current branch.

set -e

if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "Error: set ANTHROPIC_API_KEY to run this script." >&2
  exit 1
fi

cd "$(git rev-parse --show-toplevel)"
git fetch origin master 2>/dev/null || true

REPORT_FILE=$(mktemp)
trap 'rm -f "$REPORT_FILE"' EXIT

echo "Running documentation analysis and applying changes (Claude may edit files)..."
claude -p \
  --max-turns 35 \
  --allowedTools "Read" "Grep" "Glob" "Write" "Edit" "Bash(git diff *)" "Bash(git log *)" "Bash(git show *)" "Bash(cat *)" \
  <<PROMPT
You are analyzing the jit_preloader repository (a Ruby gem for N+1 preloading in Rails) to recommend documentation updates.

CONTEXT:
- This workflow runs on a branch. Compare the current branch to origin/master to see what code changed.
- Use: git diff origin/master...HEAD --name-only (and git diff origin/master...HEAD for full diffs) to list and inspect changes.
- Repo structure: README.md (main user-facing docs), lib/ (gem code), spec/ (tests), jit_preloader.gemspec. No separate dev-docs or Confluence.

YOUR TASK (two parts):

PART 1 – Report
For the code changes between this branch and master, identify what documentation should be updated or created. Consider:
1. **README.md** – usage, installation, examples, and "What it doesn't solve" / "Consequences" that might be affected or missing
2. **Code documentation** – inline comments, YARD/rdoc in lib/, and method/class docs that should reflect new behaviour or APIs
3. **Other** – CHANGELOG (if present), contributing guidelines, gem summary/description in jit_preloader.gemspec, or any other docs you think are relevant

First, produce a clear structured report. You MUST write this exact report to the file at: $REPORT_FILE
Use this format in that file:

## Documentation change suggestions

### 1. README.md
- (bullet list of specific sections and suggested changes, or "None identified")

### 2. Code documentation
- (bullet list of files in lib/ and suggested comment/YARD updates, or "None identified")

### 3. Other
- (bullet list or "None identified")

### Summary
(Short overall summary and priority if applicable.)

Also print the same report to stdout so the user sees it.

PART 2 – Apply changes
Apply the documentation changes you recommended. Edit the actual files (README.md, files in lib/, etc.) so the docs match the code. If you identified no changes or only external/Confluence items, do nothing. Do NOT run any git commands (no commit, push, or branch); the script will create the branch and PR.

RULES:
- Use only Read, Grep, Glob, and the allowed Bash commands to explore; base recommendations on the actual diff (origin/master...HEAD). If there are no code changes, say so and do not edit.
- Be specific in the report (e.g. "Update README: add section on X because the API now does Y").
- If the change is purely refactor or trivial and needs no doc updates, say that and do not edit.

Start by running the git diff commands to see what changed, then read the relevant changed files and existing docs, then write your report to $REPORT_FILE and to stdout, then apply the changes.
PROMPT

if [[ -z "$(git status --porcelain)" ]]; then
  echo "No files were modified; skipping branch and PR."
  exit 0
fi

BASE_BRANCH=$(git branch --show-current)
BRANCH="dev-docs/-${BASE_BRANCH//\//-}"
echo "Creating branch $BRANCH, committing, pushing, and opening PR..."
git checkout -b "$BRANCH"
git add -A
git commit -m "Apply suggested documentation updates"
git push -u origin "$BRANCH"

PR_BODY="Auto-generated from local documentation impact analysis (script/ci/create_dev_documentation_pr.sh)."
if [[ -s "$REPORT_FILE" ]]; then
  PR_BODY="${PR_BODY}

<details>
<summary>Documentation change suggestions</summary>

$(cat "$REPORT_FILE")
</details>"
fi

BODY_FILE=$(mktemp)
trap 'rm -f "$REPORT_FILE" "$BODY_FILE"' EXIT
printf '%s' "$PR_BODY" > "$BODY_FILE"

gh pr create --base "$BASE_BRANCH" --head "$BRANCH" \
  --title "${BASE_BRANCH} - Dev documentation updates" \
  --body-file "$BODY_FILE"

echo "Done. PR created for branch $BRANCH."
