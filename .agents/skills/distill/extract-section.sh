#!/usr/bin/env bash
# Print one section of a vault note exactly as committed (HEAD): from its
# heading to the next heading of the same or higher level. Lines inside
# fenced code blocks (``` or ~~~) are never treated as headings, so a
# "# ci.yaml" comment in a YAML block doesn't end the section.
#
# Usage: extract-section.sh "<path relative to the vault>" "<heading text, without the #s>"
# The vault defaults to ~/Desktop/knowledge_base; set VAULT to override.
# It is a script, not a one-liner in SKILL.md, because some harnesses
# substitute $0 and $1 in skill text, which breaks awk.
set -euo pipefail
if [ $# -ne 2 ]; then
  echo "usage: $(basename "$0") <note path> <heading text>" >&2
  exit 2
fi
vault="${VAULT:-$HOME/Desktop/knowledge_base}"
git -C "$vault" show "HEAD:$1" | awk -v h="$2" '
  /^(```|~~~)/ { fence = !fence }
  !fence && /^#+ / {
    match($0, /^#+/); l = RLENGTH; t = substr($0, l + 2)
    if (t == h) { on = 1; lvl = l; print; next }
    if (on && l <= lvl) exit
  }
  on'
