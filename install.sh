#!/bin/sh
set -eu

force=0
print_only=0
for arg in "$@"; do
    case "$arg" in
        --force) force=1 ;;
        --print|--print-only) print_only=1 ;;
        -h|--help) echo "usage: install.sh [--force] [--print]"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

RAW_BASE="${CLAUDE_QUOTA_RAW_BASE:-https://raw.githubusercontent.com/brhelwig/claude-quota-statusline/main}"
dest="$HOME/.claude/statusline-quota.sh"
settings="$HOME/.claude/settings.json"

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required (brew install jq / apt install jq)." >&2; exit 1; }

cleanup=""
trap '[ -n "$cleanup" ] && rm -f "$cleanup"' EXIT
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || src_dir="."
src="$src_dir/statusline-quota.sh"
if [ ! -f "$src" ]; then
    tmp=$(mktemp) || { echo "error: mktemp failed" >&2; exit 1; }
    cleanup="$tmp"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$RAW_BASE/statusline-quota.sh" -o "$tmp" \
            || { echo "error: could not download statusline-quota.sh from $RAW_BASE (is the repo public?)" >&2; exit 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp" "$RAW_BASE/statusline-quota.sh" \
            || { echo "error: could not download statusline-quota.sh from $RAW_BASE (is the repo public?)" >&2; exit 1; }
    else
        echo "error: need curl or wget to fetch statusline-quota.sh (or run install.sh from a clone)" >&2
        exit 1
    fi
    src="$tmp"
fi

mkdir -p "$HOME/.claude"
cp "$src" "$dest"
chmod 0755 "$dest"
echo "installed script: $dest"

snippet() {
    printf '  "statusLine": {\n    "type": "command",\n    "command": "%s"\n  }\n' "$dest"
}

if [ "$print_only" -eq 1 ]; then
    echo
    echo "Add this to $settings:"
    echo
    snippet
    exit 0
fi

if [ ! -f "$settings" ]; then
    echo '{}' > "$settings"
elif ! jq -e . "$settings" >/dev/null 2>&1; then
    echo "error: $settings is not valid JSON; not touching it. Add this manually:" >&2
    echo >&2
    snippet >&2
    exit 1
fi

existing=$(jq -r '.statusLine.command // empty' "$settings")

if [ "$existing" = "$dest" ]; then
    echo "already wired: settings.json statusLine points at $dest"
    exit 0
fi

if [ -n "$existing" ] && [ "$force" -ne 1 ]; then
    echo
    echo "You already have a statusLine configured:"
    echo "    $existing"
    echo "Left it untouched. To replace it with these bars:   ./install.sh --force"
    exit 0
fi

backup="$settings.bak-$(date +%Y%m%d%H%M%S)"
cp "$settings" "$backup"
stmp="$settings.tmp.$$"
jq --arg cmd "$dest" '.statusLine = {type: "command", command: $cmd}' "$settings" > "$stmp"
mv "$stmp" "$settings"

echo "wired up: settings.json statusLine -> $dest"
echo "backup:   $backup"
echo "Restart or refresh Claude Code to see the bars."
