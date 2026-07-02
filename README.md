# claude-quota-statusline

**5h / 7d usage pace** for the Claude Code status bar — the real `/usage`
percentages compared against how much of each window has elapsed, right in your
prompt line.

```
5h ▕███████▒▏ 82% used vs 99% elapsed → UNDER · resets 1m · 7d ▕█░░░░░░░▏ 14% used vs 13% elapsed → on pace · resets 6d8h
```

Each window gets a two-tone **bar** (solid █ = quota used, mid-tone = gap to the
time-elapsed mark, faint ░ = remaining) followed by **used %** vs **elapsed %**
and a verdict:

| Verdict | Meaning | Color |
|---|---|---|
| **OVER** | used is >5 pts above elapsed — burning faster than the clock | red |
| **UNDER** | used is >5 pts below elapsed — you have headroom | green |
| **on pace** | within 5 pts of elapsed | grey |

`5h` elapsed is plain calendar time; `7d` counts **weekday seconds only**
(Mon–Fri), so it tracks a 5-day work week rather than a raw 168h. `resets` is the
wall-clock time until that window rolls over.

It also tees the real snapshot (with `elapsed_percentage`, `resets_at`
normalized to epoch seconds) to `~/.local/state/claude-quota-guard/usage.json`,
so companion tools that pause/resume around quota resets have exact reset times.

## Requirements

`jq`, `awk`, and `date` — standard on macOS and Linux. No build step.

- macOS: `brew install jq`
- Debian/Ubuntu: `sudo apt install jq`

## Install

**One-liner** (works when the repo is public):

```sh
curl -fsSL https://raw.githubusercontent.com/brhelwig/claude-quota-statusline/main/install.sh | sh
```

Pass options after `-s --`, e.g. replace an existing statusline:

```sh
curl -fsSL https://raw.githubusercontent.com/brhelwig/claude-quota-statusline/main/install.sh | sh -s -- --force
```

**From a clone** (works while the repo is private):

```sh
gh repo clone brhelwig/claude-quota-statusline
cd claude-quota-statusline
./install.sh
```

Either way, `install.sh` puts `statusline-quota.sh` at `~/.claude/statusline-quota.sh`
(downloading it from the repo if you used the one-liner) **and wires it into
`~/.claude/settings.json` for you** (backing the file up first). Restart or
refresh Claude Code and the bars appear.

It won't clobber an existing statusline: if you already have a different
`statusLine` configured, it leaves it alone and tells you how to proceed.

```
./install.sh           copy + wire it up (skips wiring if another statusLine exists)
./install.sh --force   replace an existing statusLine with these bars (backup made)
./install.sh --print   copy only; print the settings snippet, change nothing
```

Requires `jq` (used to edit `settings.json` safely).

## Composing with an existing statusline

`statusLine.command` can only be one script, and stdin (the payload Claude Code
sends) can be read only once. So if you already have a statusline, capture the
payload yourself, then feed it to this script as a **separate process** and use
its output:

```sh
#!/bin/sh
input=$(cat)                 # read Claude's JSON once

# ... your existing prompt (host, dir, git, whatever) ...

quota=$(printf '%s' "$input" | "$HOME/.claude/statusline-quota.sh")
printf "%s  %s" "$my_prompt" "$quota"
```

Run it as a separate process (the pipe above), **not** via `source`/`.` — the
script uses `exit 0` on empty-data paths, which would abort your whole prompt if
sourced. Piping the captured `$input` back in avoids the "stdin read once"
problem without that risk.

## How the data gets here

Claude Code passes the real usage data to your `statusLine` command on stdin —
`rate_limits.five_hour.used_percentage`, `.resets_at`, and the 7-day
equivalents. This script just reads those fields and draws them; nothing is
estimated or scraped.

## License

[MIT](LICENSE) © Brandon Helwig
