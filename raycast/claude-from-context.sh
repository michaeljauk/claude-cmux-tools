#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Claude from Context
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖
# @raycast.packageName cmux
# @raycast.description New cmux tab with Claude for the Linear issue, GitHub PR, page or window in front; you add the instructions.

# Where the reference comes from:
#   Linear desktop -> sends Linear's "Copy issue URL" shortcut (cmd+shift+,), reads the clipboard
#   Chrome/Safari  -> URL and title of the active tab
#   any other app  -> the clipboard, if it holds an http(s) URL
#   no URL at all  -> a screenshot of the front window (Outlook, Teams, Excel, ...)
# A Linear issue or review finds its GitHub PR, and a PR finds its issue key (needs gh).
# If a cmux tab title already names the key or PR number, that tab gets focus. Otherwise
# claude-handover opens a tab whose shell line reads  claude "Context: … - "  for you to finish.
#
# Test hooks: CCT_URL=<url> (+ CCT_PAGE_TITLE) skips app detection; CCT_SHOT=<png> (+ CCT_SHOT_APP,
# CCT_SHOT_TITLE) fakes a screenshot; CCT_DRY_RUN=1 prints the decision and opens nothing.

export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
config=${CCT_CONFIG:-$HOME/.config/claude-cmux-tools/config.zsh}
dir=${CCT_STATE_DIR:-$HOME/.local/state/claude-cmux-tools}

fail() { print -r -- "Claude from Context: $1"; exit 1; }

typeset -a CCT_CONTEXTS CCT_NO_URL_ROUTES
[[ -r $config ]] && source $config
[[ -n $CCT_CLAUDE_CMD ]] && export CCT_CLAUDE_CMD
whence -p claude-handover >/dev/null || fail "claude-handover is not on PATH"

front=$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null)

url=${CCT_URL:-} page_title=${CCT_PAGE_TITLE:-}
[[ -n $url || -n $CCT_SHOT ]] && front=test
case $front in
  test) ;;
  com.linear)
    page_title=$(osascript -e 'tell application "System Events" to get name of front window of (first process whose bundle identifier is "com.linear")' 2>/dev/null)
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
    url=$(osascript -e 'tell application "Google Chrome" to get URL of active tab of front window' 2>/dev/null)
    page_title=$(osascript -e 'tell application "Google Chrome" to get title of active tab of front window' 2>/dev/null) ;;
  com.apple.Safari)
    url=$(osascript -e 'tell application "Safari" to get URL of front document' 2>/dev/null)
    page_title=$(osascript -e 'tell application "Safari" to get name of front document' 2>/dev/null) ;;
  *)
    url=$(pbpaste 2>/dev/null) ;;
esac

setopt extendedglob
url=${${url##[[:space:]]#}%%[[:space:]]#}

# No URL from the app or the clipboard: take a screenshot of the front window instead.
# Needs Screen Recording for Raycast; macOS asks once. Not for cmux itself.
shot=
if [[ $front != (test|com.cmuxterm.app) && ! $url =~ '^https?://' ]]; then
  win=$(osascript 2>/dev/null <<OSA
tell application "System Events"
  set p to first application process whose bundle identifier is "$front"
  set w to front window of p
  set {x, y} to position of w
  set {ww, hh} to size of w
  return (name of p) & tab & (name of w) & tab & x & "," & y & "," & ww & "," & hh
end tell
OSA
)
  if [[ -n $win ]]; then
    shot_app=${win%%$'\t'*} rest=${win#*$'\t'}
    shot_title=${rest%$'\t'*} shot_rect=${rest##*$'\t'}
    mkdir -p -m 700 $dir
    shot=$dir/$(date +%Y-%m-%d-%H%M%S)-screenshot.png
    ( umask 077; screencapture -x -R $shot_rect $shot ) 2>/dev/null
    [[ -s $shot ]] || fail "screenshot failed; allow Raycast under Screen Recording"
  fi
fi
[[ -n $CCT_SHOT ]] && shot=$CCT_SHOT shot_app=${CCT_SHOT_APP:-App} shot_title=${CCT_SHOT_TITLE:-}

# Keep only a single plain http(s) URL. Anything else does not reach the prompt.
if [[ -z $shot ]]; then
  [[ $url =~ '^https?://[^[:space:]]+$' && ${#url} -le 500 ]] \
    || fail "no URL found (app: ${front:-unknown})"
fi

# Window and page titles are untrusted text: one line, no control characters, capped.
clean() {
  local v=${1//[[:cntrl:]]/ }
  v=${${v##[[:space:]]#}%%[[:space:]]#}
  v=${v//[[:space:]]##/ }
  (( ${#v} > ${2:-80} )) && v="${v[1,$(( ${2:-80} - 1 ))]}…"
  print -r -- $v
}
page_title=$(clean "$page_title" 80)
gh_t() { whence -p gh >/dev/null && perl -e 'alarm shift; exec @ARGV' 4 gh "$@" 2>/dev/null; }

# First CCT_CONTEXTS entry for <kind> and <match>: prints "cwd<TAB>workspace<TAB>repo".
context_for() {
  local entry kind rest
  local -a parts
  for entry in $CCT_CONTEXTS; do
    kind=${entry%%:*} rest=${entry#*:}
    parts=("${(@s:|:)rest}")
    if [[ $kind == $1 && ${(L)parts[1]} == ${(L)2} ]]; then
      print -r -- "${parts[2]}"$'\t'"${parts[3]}"$'\t'"${parts[4]}"
      return 0
    fi
  done
  return 1
}

cwd= ws_title= key= pr= gh_repo= branch= kind= matched=
if [[ -n $shot ]]; then
  shot_app=$(clean "$shot_app" 40) shot_title=$(clean "$shot_title" 80)
  cwd=${CCT_NO_URL_CWD:-$HOME} ws_title=${CCT_NO_URL_WORKSPACE:-}
  # The window title picks the workspace, e.g. Outlook's "Inbox • you@acme.com".
  for route in $CCT_NO_URL_ROUTES; do
    [[ ${(L)shot_title} == ${(L)~${route%|*}} ]] && { ws_title=${route##*|}; break; }
  done
  ref="📷 $(clean "${shot_title:-$shot_app}" 36)"
  slug=shot
  context="Screenshot of $shot_app${shot_title:+ ($shot_title)}: $shot"
# Linear issue (/issue/ABC-123/...) or Linear review of its PR (/review/abc-123-<slug>-<hash>).
elif [[ $url =~ 'linear\.app/([^/]+)/(issue|review)/([A-Za-z]+-[0-9]+)' ]]; then
  org=$match[1] kind="Linear $match[2]" key=${(U)match[3]}
  if matched=$(context_for linear $org); then
    gh_repo=${${matched#*$'\t'}#*$'\t'}
  fi
  if [[ -n $gh_repo ]]; then
    # The PR whose title starts with the key; an open one first, then the newest.
    found=$(gh_t pr list -R $gh_repo --state all --search "$key in:title" --limit 10 \
      --json number,state,title,headRefName \
      --jq "[.[] | select(.title | test(\"^$key\\\\b\"; \"i\"))] | sort_by(.state != \"OPEN\") | .[0] // empty | \"\(.number) \(.headRefName)\"")
    [[ -n $found ]] && pr=${found%% *} branch=${found#* }
  fi
elif [[ $url =~ 'github\.com/([^/]+/[^/]+)/pull/([0-9]+)' ]]; then
  gh_repo=$match[1] pr=$match[2] kind=GitHub
  matched=$(context_for github $gh_repo)
  # The issue key from the PR title ("ABC-123: ...") or the branch ("feature/ABC-123-...").
  found=$(gh_t pr view $pr -R $gh_repo --json title,headRefName --jq '"\(.headRefName) \(.title)"')
  if [[ -n $found ]]; then
    branch=${found%% *}
    # zsh regex on macOS has no \b, so the boundary is spelled out.
    [[ $found =~ '(^|[^A-Za-z0-9])([A-Z][A-Z0-9]+-[0-9]+)([^0-9]|$)' ]] && key=$match[2]
  fi
fi

if [[ -n $shot ]]; then
  :  # ref, slug and context are set above
elif [[ -n $key || -n $pr ]]; then
  ref=$key
  [[ -n $pr ]] && ref=${ref:+$ref · }"PR #$pr"
  slug=${key:-pr-$pr}
  [[ -n $key && -n $pr ]] && slug=$key-pr-$pr
  if [[ $kind == GitHub ]]; then
    context="GitHub PR #$pr"; [[ -n $key ]] && context+=" = Linear $key"
  else
    context="$kind $key"; [[ -n $pr ]] && context+=" = GitHub PR #$pr"
  fi
  [[ -n $gh_repo ]] && context+=" in $gh_repo"
  [[ -n $branch ]] && context+=" (branch $branch)"
  context+=": $url"
else
  # Plain link: the page title, else host · last path segment.
  # Not "path": in zsh that is tied to $PATH, and assigning it wipes PATH.
  host=${${url#*://}%%/*} url_path=${${${url#*://}#*/}%%[?#]*}
  [[ $url_path == ${url#*://} ]] && url_path=
  last=${url_path%/}; last=${last##*/}
  ref=${page_title:-$host${last:+ · $last}}
  (( ${#ref} > 40 )) && ref="${ref[1,39]}…"
  slug=link
  context=${page_title:+"$page_title: "}$url
fi

# A matching CCT_CONTEXTS entry sets folder and workspace.
if [[ -n $matched ]]; then
  cwd=${matched%%$'\t'*} rest=${matched#*$'\t'}
  ws_title=${rest%%$'\t'*}
fi
# Without a context or a screenshot rule: the focused workspace and the folder of its selected
# tab (cmux current_directory), so the claude router picks the plan for that place.
if [[ -z $cwd ]]; then
  cwd=$(CMUX_QUIET=1 cmux --json --id-format uuids workspace list 2>/dev/null | jq -r \
    --arg id "$(CMUX_QUIET=1 cmux --json --id-format uuids identify 2>/dev/null | jq -r '.focused.workspace_id // empty')" \
    '.workspaces[] | select(.id == $id) | .current_directory // empty')
fi
[[ -n $cwd && -d $cwd ]] || cwd=${CCT_DEFAULT_CWD:-$HOME}

# Workspace by title, leading emoji and spaces ignored ("🚀 Acme" = "Acme"). No match: focused.
ws=
if [[ -n $ws_title ]]; then
  ws=$(CMUX_QUIET=1 cmux --json --id-format uuids workspace list 2>/dev/null | jq -r --arg t "$ws_title" \
    '[.workspaces[] | select((.title | sub("^[^[:alnum:]]+"; "") | ascii_downcase) == ($t | ascii_downcase)) | .id][0] // empty')
fi

# An existing tab that names the issue key or the PR number wins; a tab in the target workspace
# first. Plain links and screenshots never match. The PR pattern also matches "#123" alone.
patterns=()
[[ -n $key ]] && patterns+=("\\b${key}\\b")
[[ -n $pr ]] && patterns+=("(\\bPR\\s*#?|#)${pr}\\b")
pattern=${(j:|:)patterns}
existing=
if [[ -n $pattern ]]; then
  existing=$(CMUX_QUIET=1 cmux --json --id-format uuids tree --all 2>/dev/null | jq -r --arg re "$pattern" --arg ws "$ws" '
    [.windows[].workspaces[] as $w | $w.panes[].surfaces[]
      | select(.type == "terminal" and ((.title // "") | test($re; "i")))
      | {id, title, mine: ($w.id == $ws)}]
    | (map(select(.mine)) + map(select(.mine | not)))[0] // empty | "\(.id)\t\(.title)"')
fi

if [[ -n $CCT_DRY_RUN ]]; then
  # The real run needs these after the parsing above; a clobbered PATH shows up here.
  for t in date chmod cmux jq claude-handover; do whence -p $t >/dev/null || print -r -- "MISSING $t"; done
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

# The context lands on the tab's shell line; you type your instructions after it and press Enter.
mkdir -p -m 700 $dir
prompt_file=$dir/$(date +%Y-%m-%d-%H%M%S)-$slug.md
print -rn -- "Context: $context - " > $prompt_file
chmod 600 $prompt_file

out=$(claude-handover $prompt_file --cwd $cwd --title $ref --prefill ${ws:+--workspace} ${ws:+$ws} 2>&1) \
  || fail "${out##*$'\n'}"
[[ -n $ws ]] && CMUX_QUIET=1 cmux workspace select --workspace $ws >/dev/null 2>&1
open -a cmux
print -r -- "Claude tab: $ref"
