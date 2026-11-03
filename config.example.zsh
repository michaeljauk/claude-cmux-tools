# claude-cmux-tools configuration.
# Copy to ~/.config/claude-cmux-tools/config.zsh and edit. Both claude-router and the Raycast
# command source this file. It is plain zsh, so $HOME and quoting work as usual.

# --- claude-router -------------------------------------------------------------------------

# Accounts: name -> CLAUDE_CONFIG_DIR. An empty value means Claude Code's default (~/.claude).
# Log in once per account: CLAUDE_CONFIG_DIR=<dir> claude, then /login.
typeset -A CCT_ACCOUNTS=(
  personal ""
  work     "$HOME/.claude-work"
)

# Account used when no route matches.
CCT_DEFAULT_ACCOUNT=personal

# Routes, first match wins. Format: "<kind>:<pattern>|<account>"
#   workspace:<glob>  the cmux workspace title matches <glob> (case-insensitive)
#   path:<dir>        $PWD is <dir> or below it
#   remote:<glob>     the git "origin" URL of $PWD matches <glob>
# CLAUDE_ACCOUNT=<name> in the environment overrides every route.
CCT_ROUTES=(
  "workspace:*acme*|work"
  "path:$HOME/acme|work"
  "remote:*github.com?acme-inc/*|work"
)

# MCP servers added with the default account live in ~/.claude.json. If true, the router hands
# the user-scope and project-scope servers to the other accounts on every start.
CCT_SHARE_MCP=false

# Path of the real claude binary. Default: ~/.local/bin/claude (native installer).
# CCT_CLAUDE_BIN=$HOME/.local/bin/claude

# --- claude-handover -------------------------------------------------------------------------

# Command that --prefill puts on the tab's shell line. Default: claude. Use your alias if you have
# one, for example c.
# CCT_CLAUDE_CMD=claude

# --- Raycast "Claude from Context" ---------------------------------------------------------

# Where a Linear issue or GitHub PR opens.
# Format: "<kind>:<match>|<cwd>|<workspace title>|<github owner/repo>"
#   linear:<org>         https://linear.app/<org>/issue/KEY-123/... (and /review/... links)
#   github:<owner/repo>  https://github.com/<owner/repo>/pull/123
# The 4th field (Linear only) lets an issue find its PR through gh. The workspace title is compared
# without leading emoji and spaces, so "Acme" matches the workspace "🚀 Acme". Leave it empty to
# use the focused workspace.
CCT_CONTEXTS=(
  "linear:acme|$HOME/acme/monorepo|Acme|acme-inc/monorepo"
  "github:acme-inc/monorepo|$HOME/acme/monorepo|Acme"
)

# Everything without a URL (a screenshot of Outlook, Teams, Excel, ...) starts here.
CCT_NO_URL_CWD=$HOME/notes
# Workspace for those tabs; empty = the focused workspace.
CCT_NO_URL_WORKSPACE="Notes"
# Window-title globs that pick another workspace, first match wins. Format: "<glob>|<workspace>"
# Outlook's title holds the selected mailbox, e.g. "Inbox • you@acme.com".
CCT_NO_URL_ROUTES=(
  "*@acme.com*|Notes / Acme"
)

# Folder when nothing else gives one (no context, no usable cmux folder).
CCT_DEFAULT_CWD=$HOME
