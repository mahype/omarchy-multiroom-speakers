#!/bin/bash
# Collects everything needed to find out why a room stayed silent: the
# plugin's own log, OwnTone's log, PipeWire's AirPlay messages and the current
# state of sinks, modules and speakers. Prints to stdout.
#
# Usage: tools/collect-logs.sh [minutes]   (default: last 60 minutes)

set -uo pipefail

MIN="${1:-60}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-multiroom-speakers"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-multiroom-speakers/config.json"
UNIT=omarchy-multiroom-speakers-owntone
SINCE=$(date -d "-$MIN min" '+%Y-%m-%d %H:%M:%S')
SINCE_ISO=$(date -u -d "-$MIN min" '+%Y-%m-%dT%H:%M:%S')

section() { printf '\n===== %s =====\n' "$1"; }

section "time"
date
section "config.json"
cat "$CONFIG" 2>&1
section "default output"
pactl get-default-sink 2>&1
section "plugin modules"
pactl list modules short 2>&1 | grep -E $'^[0-9]+\tmodule-(raop-discover|pipe-sink|combine-sink)'
section "sinks (plugin and AirPlay)"
pactl -f json list sinks 2>/dev/null | jq -r '.[] | select(.name|test("^(raop_sink|omarchy_)")) |
  [.name, .state, ([.volume[]?.value_percent] | first // "-"), (if .mute then "muted" else "" end)] | @tsv'
section "streams"
pactl -f json list sink-inputs 2>/dev/null | jq -r '.[] |
  [.index, .sink, .properties["application.name"], (if .corked then "paused" else "playing" end)] | @tsv'
section "OwnTone unit"
systemctl --user status "$UNIT" --no-pager 2>&1 | head -6
section "OwnTone player"
curl -s -m 3 http://127.0.0.1:3689/api/player 2>&1 | jq -c '{state, volume, item_progress_ms}' 2>/dev/null
section "OwnTone outputs"
curl -s -m 3 http://127.0.0.1:3689/api/outputs 2>&1 |
  jq -r '.outputs[] | [.id, .name, .type, (if .selected then "selected" else "" end), .volume, .offset_ms] | @tsv' 2>/dev/null
section "plugin.log (since $SINCE_ISO UTC)"
awk -v since="$SINCE_ISO" 'substr($1,1,19) >= since' "$STATE/plugin.log" 2>/dev/null | tail -400
section "owntone.log (since $SINCE)"
awk -v since="[$SINCE" 'substr($0,1,20) >= since' "$STATE/owntone.log" 2>/dev/null |
  grep -av "Could not open pipe for reading .*metadata" | tail -400
section "PipeWire AirPlay messages"
journalctl --user -u pipewire -u pipewire-pulse --since "$SINCE" --no-pager 2>/dev/null |
  grep -iE "raop|airplay|rtsp|combine|pipe" | tail -200
