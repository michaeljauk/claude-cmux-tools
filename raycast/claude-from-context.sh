#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Claude from Context
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖
# @raycast.packageName cmux
# @raycast.description New cmux tab with Claude; the Linear issue, GitHub PR or URL in front is pre-filled, not sent.

# Where the reference comes from:
#   Linear desktop -> sends Linear's "Copy issue URL" shortcut (cmd+shift+,), reads the clipboard
#   Chrome/Safari  -> URL of the active tab
#   any other app  -> the clipboard, if it holds an http(s) URL
# If a cmux tab already names the issue key or PR number in its title, that tab gets focus.
# Otherwise claude-handover opens a new tab; CCT_CONTEXTS in the config picks folder and workspace.
#
# Test hooks: CCT_URL=<url> skips app detection; CCT_DRY_RUN=1 prints the decision, opens nothing.

export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
config=${CCT_CONFIG:-$HOME/.config/claude-cmux-tools/config.zsh}
dir=${CCT_STATE_DIR:-$HOME/.local/state/claude-cmux-tools}

fail() { print -r -- "Claude from Context: $1"; exit 1; }

typeset -a CCT_CONTEXTS
[[ -r $config ]] && source $config
default_cwd=${CCT_DEFAULT_CWD:-$HOME}
whence -p claude-handover >/dev/null || fail "claude-handover is not on PATH"

front=$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null)

url=${CCT_URL:-}
[[ -n $url ]] && front=test
case $front in
  test) ;;
  com.linear)
    saved=$(pbpaste 2>/dev/null)
    print -n '' | pbcopy
    osascript -e 'tell application "System Events" to keystroke "," using {command down, shift down}' \
      || fail "Raycast needs Accessibility permission to send the Linear shortcut"
    for _ in {1..20}; do
      url=$(pbpaste 2>/dev/null)
      [[ -n $url ]] && break
      sleep 0.1
    done
    # Put the old text back. Non-text clipboard content (images, files) is lost.
    print -rn -- "$saved" | pbcopy
    ;;
  com.google.Chrome)
    url=$(osascript -e 'tell application "Google Chrome" to get URL of active tab of front window' 2>/dev/null) ;;
  com.apple.Safari)
    url=$(osascript -e 'tell application "Safari" to get URL of front document' 2>/dev/null) ;;
  *)
    url=$(pbpaste 2>/dev/null) ;;
esac

# Keep only a single plain http(s) URL. Anything else does not reach the prompt.
setopt extendedglob
url=${${url##[[:space:]]#}%%[[:space:]]#}
[[ $url =~ '^https?://[^[:space:]]+$' && ${#url} -le 500 ]] \
  || fail "no URL found (app: ${front:-unknown})"

# What is it? kind + match feed the CCT_CONTEXTS lookup below.
kind= match_key=
if [[ $url =~ 'linear\.app/([^/]+)/issue/([A-Za-z]+-[0-9]+)' ]]; then
  kind=linear match_key=$match[1]
  ref=${(U)match[2]}
  slug=$ref
  context="Linear issue $ref: $url"
elif [[ $url =~ 'github\.com/([^/]+/[^/]+)/pull/([0-9]+)' ]]; then
  kind=github match_key=$match[1]
  ref="PR #$match[2]"
  slug=pr-$match[2]
  context="GitHub $ref in $match_key: $url"
else
  ref=link slug=link
  context=$url
fi

# Folder and workspace title from the first matching context.
cwd=$default_cwd ws_title=
for entry in $CCT_CONTEXTS; do
  local_kind=${entry%%:*} rest=${entry#*:}
  parts=("${(@s:|:)rest}")
  if [[ -n $kind && $local_kind == $kind && ${(L)parts[1]} == ${(L)match_key} ]]; then
    cwd=${parts[2]:-$default_cwd}
    ws_title=${parts[3]}
    break
  fi
done
[[ -d $cwd ]] || fail "folder does not exist: $cwd"

# Workspace by title, leading emoji and spaces ignored. No match: the focused workspace.
ws=
if [[ -n $ws_title ]]; then
  ws=$(CMUX_QUIET=1 cmux --json --id-format uuids workspace list 2>/dev/null \
    | jq -r --arg t "$ws_title" '[.workspaces[]
        | select((.title | sub("^[^[:alnum:]]+"; "") | ascii_downcase) == ($t | ascii_downcase))
        | .id][0] // empty')
fi

# An existing tab that names the key or PR number wins. A tab in the target workspace first.
# Plain links never match. The PR pattern also matches "#123" alone.
pattern=
case $slug in
  pr-*) pattern="(\\bPR\\s*#?|#)${slug#pr-}\\b" ;;
  link) ;;
  *) pattern="\\b${slug}\\b" ;;
esac
existing=
if [[ -n $pattern ]]; then
  existing=$(CMUX_QUIET=1 cmux --json --id-format uuids tree --all 2>/dev/null | jq -r --arg re "$pattern" --arg ws "$ws" '
    [.windows[].workspaces[] as $w | $w.panes[].surfaces[]
      | select(.type == "terminal" and ((.title // "") | test($re; "i")))
      | {id, title, mine: ($w.id == $ws)}]
    | (map(select(.mine)) + map(select(.mine | not)))[0] // empty | "\(.id)\t\(.title)"')
fi

if [[ -n $CCT_DRY_RUN ]]; then
  print -r -- "cwd=$cwd title=$ref workspace=${ws:-focused} existing=${existing:-none}"
  print -r -- "Context: $context"
  exit 0
fi

if [[ -n $existing ]]; then
  CMUX_QUIET=1 cmux rpc surface.focus "$(jq -nc --arg s ${existing%%$'\t'*} '{surface_id: $s}')" >/dev/null 2>&1 \
    || fail "could not focus the existing tab: ${existing#*$'\t'}"
  open -a cmux
  print -r -- "Existing tab: ${existing#*$'\t'}"
  exit 0
fi

# The context goes into Claude's input box unsent; you type your instructions after it.
mkdir -p -m 700 $dir
prompt_file=$dir/$(date +%Y-%m-%d-%H%M%S)-$slug.md
print -r -- "Context: $context" > $prompt_file
print -r -- "" >> $prompt_file
chmod 600 $prompt_file

out=$(claude-handover $prompt_file --cwd $cwd --title $ref --prefill ${ws:+--workspace} ${ws:+$ws} 2>&1) \
  || fail "${out##*$'\n'}"
[[ -n $ws ]] && CMUX_QUIET=1 cmux workspace select --workspace $ws >/dev/null 2>&1
open -a cmux
print -r -- "Claude tab: $ref"
