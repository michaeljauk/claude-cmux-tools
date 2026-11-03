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

# --- Raycast "Claude from Context" ---------------------------------------------------------

# Where a Linear issue or GitHub PR opens. Format: "<kind>:<match>|<cwd>|<workspace title>"
#   linear:<org>         https://linear.app/<org>/issue/KEY-123/...
#   github:<owner/repo>  https://github.com/<owner/repo>/pull/123
# The workspace title is compared without leading emoji and spaces, so "Acme" matches the
# workspace "🚀 Acme". Leave it empty to use the focused workspace.
CCT_CONTEXTS=(
  "linear:acme|$HOME/acme/monorepo|Acme"
  "github:acme-inc/monorepo|$HOME/acme/monorepo|Acme"
)

# Folder for everything that matches no context (other repos, plain links).
CCT_DEFAULT_CWD=$HOME
