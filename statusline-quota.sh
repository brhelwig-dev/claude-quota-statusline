#!/bin/sh
[ -n "$input" ] || input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

JQ_ELAPSED='
  def to_epoch: if .==null then null elif type=="number" then (if .>1e12 then ./1000 else . end) else (try fromdateiso8601 catch null) end;
  def clamppct: if . < 0 then 0 elif . > 100 then 100 else . end;
  def wsecs(a;b):
    if a >= b then 0
    else (reduce range(0;9) as $i ({t:a, acc:0};
      if .t >= b then .
      else ((.t/86400)|floor) as $day
        | (($day + 4) % 7) as $wd
        | (.t - $day*86400) as $into
        | (.t + (86400 - $into)) as $nm
        | (if $nm > b then b else $nm end) as $se
        | (if ($wd >= 1 and $wd <= 5) then ($se - .t) else 0 end) as $add
        | {t:$se, acc:(.acc + $add)} end)).acc end;
  def elapsed5($now): (.resets_at | to_epoch) as $r
    | if $r == null then null else ((($now - ($r - 18000)) / 18000 * 100) | clamppct | floor) end;
  def elapsed7($now): (.resets_at | to_epoch) as $r
    | if $r == null then null else
        ($r - 604800) as $s | (if $now > $r then $r else $now end) as $nc
        | wsecs($s; $r) as $tot
        | (if $tot <= 0 then null else ((wsecs($s; $nc) / $tot) * 100 | clamppct | floor) end) end;
'

rl=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
[ -n "$rl" ] || exit 0

enriched=$(jq -cn --argjson rl "$rl" "$JQ_ELAPSED"'
  def norm_resets: (.resets_at | to_epoch) as $r | if $r == null then . else .resets_at = ($r | floor) end;
  (now | floor) as $now
  | $rl
  | .five_hour  |= norm_resets
  | .seven_day |= norm_resets
  | .five_hour.elapsed_percentage  = (.five_hour | elapsed5($now))
  | .seven_day.elapsed_percentage = (.seven_day | elapsed7($now))' 2>/dev/null)
[ -n "$enriched" ] || exit 0

mkdir -p "$HOME/.local/state/claude-quota-guard" 2>/dev/null
printf '%s' "$enriched" | jq -c '{rate_limits: ., updated_at: (now | floor)}' \
    > "$HOME/.local/state/claude-quota-guard/usage.json" 2>/dev/null

vals=$(jq -rn --argjson rl "$enriched" "$JQ_ELAPSED"'
  def pct: if type == "number" then round else "?" end;
  def rat: (. | to_epoch) as $r | if $r == null then "?" else ($r | floor) end;
  $rl | [
    (.five_hour.used_percentage  | pct), (.five_hour.elapsed_percentage  | pct), (.five_hour.resets_at  | rat),
    (.seven_day.used_percentage | pct), (.seven_day.elapsed_percentage | pct), (.seven_day.resets_at | rat)
  ] | @tsv' 2>/dev/null)
[ -n "$vals" ] || exit 0

tab=$(printf '\t')
IFS="$tab" read -r f_u f_e f_r s_u s_e s_r <<EOF
$vals
EOF

now=$(date +%s)
is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

cqg_bar() {
    awk -v used="$1" -v elapsed="$2" -v w=8 '
        function clamp(c){ if(c<0)return 0; if(c>w)return w; return c }
        function rep(s,n,  o,i){ o=""; for(i=0;i<n;i++) o=o s; return o }
        function colr(code,str){ return sprintf("%c[%sm%s%c[0m",27,code,str,27) }
        BEGIN{
            u=clamp(int(used/100*w+0.5)); e=clamp(int(elapsed/100*w+0.5));
            if(u<=e) bar=colr("32",rep("█",u)) colr("90",rep("▒",e-u)) colr("90",rep("░",w-e));
            else { over=(used>=90)?"31":"33"; bar=colr("32",rep("█",e)) colr(over,rep("▓",u-e)) colr("90",rep("░",w-u)); }
            printf "%s%s%s", colr("90","▕"), bar, colr("90","▏");
        }'
}

fmt_window() {
    label=$1; u=$2; e=$3; r=$4
    if is_int "$u" && is_int "$e"; then
        bar=$(cqg_bar "$u" "$e")
        d=$((u - e))
        if   [ "$d" -gt 5 ];  then v="OVER";    vc=31
        elif [ "$d" -lt -5 ]; then v="UNDER";   vc=32
        else                       v="on pace"; vc=90
        fi
        out="$label $bar $u% used vs $e% elapsed → \033[${vc}m$v\033[0m"
    else
        out="$label: $u% used"
    fi
    if is_int "$r"; then
        s=$((r - now))
        if   [ "$s" -le 0 ];     then out="$out · resets now"
        elif [ "$s" -ge 86400 ]; then out="$out · resets $((s / 86400))d$(((s % 86400) / 3600))h"
        elif [ "$s" -ge 3600 ];  then out="$out · resets $((s / 3600))h$(((s % 3600) / 60))m"
        else                          out="$out · resets $((s / 60))m"
        fi
    fi
    printf '%b' "$out"
}

printf '%s · %s' "$(fmt_window 5h "$f_u" "$f_e" "$f_r")" "$(fmt_window 7d "$s_u" "$s_e" "$s_r")"
