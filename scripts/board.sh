#!/usr/bin/env bash
# Move an issue's card on the EasyPlan project board.
#   ./scripts/board.sh <issue-number> todo|progress|done
# Adds the issue to the board first if it isn't there. Needs `gh` signed in
# with the `project` scope (gh auth refresh -h github.com -s project).
set -euo pipefail

OWNER=kangjin97
REPO=kangjin97/project1.0
PROJECT=3                                   # https://github.com/users/kangjin97/projects/3
PROJECT_ID=PVT_kwHOAryeoc4Bmqnn
STATUS_FIELD=PVTSSF_lAHOAryeoc4BmqnnzhlSsGs # the board's "Status" field

issue="${1:-}"
case "${2:-}" in
  todo)     option=f75ad846 label="Todo" ;;
  progress) option=47fc9ee4 label="In Progress" ;;
  done)     option=98236657 label="Done" ;;
  *) echo "Usage: $0 <issue-number> todo|progress|done" >&2; exit 1 ;;
esac
[[ "$issue" =~ ^[0-9]+$ ]] || { echo "Issue number must be a number, e.g. 23" >&2; exit 1; }

# Adding an item that's already on the board returns the existing item.
item=$(gh project item-add "$PROJECT" --owner "$OWNER" \
  --url "https://github.com/$REPO/issues/$issue" --format json --jq .id)
gh project item-edit --id "$item" --project-id "$PROJECT_ID" \
  --field-id "$STATUS_FIELD" --single-select-option-id "$option" >/dev/null
echo "#$issue → $label"
