# claude-cmux-tools

Three small zsh scripts for people who run [Claude Code](https://code.claude.com) in
[cmux](https://cmux.com) on macOS:

| Script | What it does |
|---|---|
| `bin/claude-router` | Picks a Claude Code account (`CLAUDE_CONFIG_DIR`) from the cmux workspace, the folder or the git remote, then runs `claude`. Work repos use the work account, everything else uses the personal one. |
| `bin/claude-handover` | Opens a new cmux tab and starts Claude Code there with a prompt from a file. It can send the prompt or only pre-fill it. |
| `raycast/claude-from-context.sh` | A Raycast hotkey. It reads the Linear issue, the GitHub PR or the URL in front of you, and opens a cmux tab with Claude and that reference pre-filled. If a tab for that issue or PR already exists, it focuses that tab. |

They are personal tooling, shared as is. Expect to read and adapt them.

## Requirements

- macOS, zsh, [`jq`](https://jqlang.org)
- cmux (tested with 0.64 and 0.65)
- Claude Code with the native installer (`~/.local/bin/claude`), tested with 2.1.317
- Raycast, for the hotkey only

## Install

```sh
git clone https://github.com/michaeljauk/claude-cmux-tools ~/tech/claude-cmux-tools
mkdir -p ~/.config/claude-cmux-tools
cp ~/tech/claude-cmux-tools/config.example.zsh ~/.config/claude-cmux-tools/config.zsh
ln -s ~/tech/claude-cmux-tools/bin/claude-router ~/tech/claude-cmux-tools/bin/claude-handover ~/.local/bin/
```

Edit `~/.config/claude-cmux-tools/config.zsh`. Every setting is described in that file.

### claude-router

1. Add one entry per account to `CCT_ACCOUNTS`, then log in once per account:
   `CLAUDE_CONFIG_DIR=~/.claude-work claude`, then `/login`.
2. Add routes to `CCT_ROUTES`, for example `"path:$HOME/acme|work"`.
3. Make `claude` go through the router: `alias claude=claude-router` in `~/.zshrc`.
4. In cmux, set the same for tabs that cmux starts itself:

   ```sh
   cmux config set automation.claudeBinaryPath "\"$HOME/.local/bin/claude-router\""
   ```

Check a route without starting Claude: `CCT_DRY_RUN=1 claude-router`.
To force an account for one run, use `CLAUDE_ACCOUNT=work claude`.

The router only picks an account. It does not switch accounts when one hits a usage limit.

### claude-handover

```sh
claude-handover prompt.md --cwd ~/acme/monorepo --title "ACME-42"   # sends the prompt
claude-handover prompt.md --prefill                                  # fills the input box only
```

Inside cmux, the tab opens next to the calling tab. Outside cmux it opens in the focused
workspace, and that needs password mode (next section).

### Raycast hotkey

1. **Switch the cmux socket to password mode.** Raycast is not a cmux process, and the default
   mode (`cmuxOnly`) refuses it:

   ```sh
   cmux config set automation.socketControlMode '"password"'
   cmux config set automation.socketPassword "\"$(openssl rand -base64 30)\""
   cmux reload-config
   ```

   > **Security tradeoff.** In `cmuxOnly` mode only processes that cmux started can control
   > cmux. In password mode, any local process that knows the password can open tabs and type
   > commands into your terminals. The password is stored in plain text in
   > `~/.config/cmux/cmux.json` (mode 600). Do not use `allowAll` or `openAccess`: they need no
   > password at all.

2. In Raycast: **Settings → Extensions → Script Commands → Add Directories**, then add the
   `raycast/` folder of this repo.
3. Give **Claude from Context** a hotkey. Pick one that no app uses: ⌥⌘C, for example, opens
   the Chrome DevTools. The author uses ⌃⌥⌘C.
4. Add your Linear org and GitHub repos to `CCT_CONTEXTS`, so issues and PRs open in the right
   folder and workspace.
5. On first use, allow Raycast to control your computer (Accessibility). The Linear part sends a
   keystroke.

How it finds the reference:

| App in front | Source |
|---|---|
| Linear desktop | sends ⌘⇧, (Copy issue URL), reads the clipboard, puts the old text back |
| Chrome, Safari | URL of the active tab |
| any other app | the clipboard, if it holds an http(s) URL |

How it picks the tab:

- If a cmux tab title names the issue key (`ACME-42`) or the PR number (`PR #123`, `#123`), the
  hotkey focuses that tab. A tab in the target workspace comes first.
- If no tab matches, it opens a new tab in the folder and workspace from `CCT_CONTEXTS`. Without
  a matching context, it uses `CCT_DEFAULT_CWD` and the focused workspace.
- The new tab shows `Context: <issue, PR or URL>` in Claude's input box. Type your instructions
  after it and press Enter.

Test without opening anything:

```sh
CCT_DRY_RUN=1 CCT_URL=https://linear.app/acme/issue/ACME-42/x raycast/claude-from-context.sh
```

## Limits

- **`--prefill` is undocumented.** It is the flag that Claude Code's own `claude-cli://` deep
  links use. An update can change or remove it. If tabs open with an "unknown option" error,
  drop `--prefill` from the Raycast script.
- **Matching uses tab titles only.** A session that you started by hand matches only if its
  title contains the key.
- **Clipboard:** after the Linear step, only text comes back. An image or a file on the clipboard
  is lost.
- **One cmux window:** the workspace lookup searches the current window only. More than one
  window is not tested.
- **Linear views and projects:** ⌘⇧, copies nothing there, so the hotkey reports "no URL found".

## License

MIT, see [LICENSE](LICENSE).
