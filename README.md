# claude-cmux-tools

Three small zsh scripts for people who run [Claude Code](https://code.claude.com) in
[cmux](https://cmux.com) on macOS:

| Script | What it does |
|---|---|
| `bin/claude-router` | Picks a Claude Code account (`CLAUDE_CONFIG_DIR`) from the cmux workspace, the folder or the git remote, then runs `claude`. Work repos use the work account, everything else uses the personal one. |
| `bin/claude-handover` | Opens a new cmux tab and starts Claude Code there with a prompt from a file. It can send the prompt at once, or put it on the tab's shell line for you to finish. |
| `raycast/claude-from-context.sh` | A Raycast hotkey. It takes the Linear issue, GitHub PR, web page or window in front of you and opens a cmux tab with `claude "Context: … - "` on the shell line. You type your instructions and press Enter. If a tab for that issue or PR already exists, it focuses that tab instead. |

They are personal tooling, shared as is. Expect to read and adapt them.

## Requirements

- macOS, zsh, [`jq`](https://jqlang.org)
- cmux (tested with 0.64 and 0.65)
- Claude Code with the native installer (`~/.local/bin/claude`), tested with 2.1.317
- Raycast, for the hotkey only
- Optional: [`gh`](https://cli.github.com), logged in. Without it, issues and PRs are not linked.

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

#### API backends

`claude-router --backend <name>` runs Claude Code against an Anthropic-compatible API with an API
key, for example a provider of open-weight models. Routes never pick a backend; only the flag
does.

1. Store the key in the Keychain:
   `security add-generic-password -s example-api-key -a "$USER" -w`
2. Add an entry to `CCT_BACKENDS`: config dir, base URL, key command, model, small model.
3. Check it without starting Claude: `CCT_DRY_RUN=1 claude-router --backend example`.
   This runs the key command and prints the key length, never the key.

The provider must serve `POST <base url>/v1/messages`. Each backend has its own config dir, so its
sessions do not mix with the accounts. That dir starts empty: link your skills into it if you want
them there. Claude Code prints `unrecognized_model` for non-Claude models and shows a cost
estimate that is not the provider's price. If the key is wrong, Claude Code retries silently
instead of failing. A session that hangs at the start usually means a wrong key.

### claude-handover

```sh
claude-handover prompt.md --cwd ~/acme/monorepo --title "ACME-42"   # sends the prompt at once
claude-handover prompt.md --prefill                                  # puts it on the shell line
```

With `--prefill` the new tab shows `claude "<prompt>▌"`, with the cursor before the closing quote.
Type your text and press Enter. A one-shot zsh widget takes the line raw, before the shell parses
it, so `"`, `'`, `$`, `!` and backticks in your text arrive as typed. If you rewrite the line into
another command, it runs as usual. Ctrl+C cancels. Set `CCT_CLAUDE_CMD` to use an alias such as `c`.

cmux cannot set a shell's input line from outside, so the script types one `source <launcher>`
line into the new tab. The launcher clears the screen, sets up the widget and deletes itself.

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
4. Fill in `CCT_CONTEXTS` and the `CCT_NO_URL_*` settings in the config.
5. On first use, macOS asks twice. Allow both:
   - **Accessibility** for Raycast: the Linear step sends a keystroke.
   - **Screen Recording** for Raycast: apps without a URL get a screenshot.

#### What it reads

| App in front | Source |
|---|---|
| Linear desktop | sends ⌘⇧, (Copy issue URL), reads the clipboard, puts the old text back; the window title |
| Chrome, Safari | URL and title of the active tab |
| any other app | the clipboard, if it holds an http(s) URL |
| no URL anywhere (Outlook, Teams, Excel, …) | a screenshot of the front window, saved with mode 600 |

#### What it puts on the line

| Reference | Tab title | Context |
|---|---|---|
| Linear issue or review link | `ACME-42 · PR #123` | `Linear issue ACME-42 = GitHub PR #123 in acme-inc/monorepo (branch …): <url>` |
| GitHub PR | `ACME-42 · PR #123` | `GitHub PR #123 = Linear ACME-42 in acme-inc/monorepo (branch …): <url>` |
| other web page | page title, else `host · last segment` | `<page title>: <url>` |
| screenshot | `📷 <window title>` | `Screenshot of <app> (<window title>): <png path>` |

An issue finds its PR through `gh` by the key at the start of the PR title. A PR finds its key in
its title or branch name. The 4th field of a `linear:` context names the repo to search.

#### Which tab, folder and workspace

- If a cmux tab title names the issue key or the PR number (`ACME-42`, `PR #123`, `#123`), the
  hotkey focuses that tab. A tab in the target workspace comes first.
- A matching `CCT_CONTEXTS` entry sets the folder and the workspace.
- A screenshot starts in `CCT_NO_URL_CWD`. `CCT_NO_URL_ROUTES` picks the workspace by window title.
  Outlook's title holds the selected mailbox, so mails of one domain can go to their own workspace.
- Everything else opens in the focused workspace, in the folder of that workspace's selected tab.
  The router then picks the account for that place.

Test without opening anything:

```sh
CCT_DRY_RUN=1 CCT_URL=https://linear.app/acme/issue/ACME-42/x raycast/claude-from-context.sh
CCT_DRY_RUN=1 CCT_SHOT=/tmp/x.png CCT_SHOT_APP=Outlook CCT_SHOT_TITLE="Inbox • you@acme.com" \
  raycast/claude-from-context.sh
```

## Limits

- **Screenshots show the whole window.** Claude sees everything in it once you press Enter.
  Do not send windows with data that must not leave your machine. Old screenshots stay in
  `~/.local/state/claude-cmux-tools` until you delete them.
- **The new Outlook for Mac** exposes no mail selection over AppleScript, so mails come in as
  screenshots, not as references.
- **Matching uses tab titles only.** A session that you started by hand matches only if its
  title contains the key or PR number.
- **Clipboard:** after the Linear step, only text comes back. An image or a file on the clipboard
  is lost.
- **One cmux window:** the workspace lookup searches the current window only. More than one
  window is not tested.
- **Linear views and projects:** ⌘⇧, copies nothing there. The window then gets a screenshot.
- **The shell line is one zsh line.** For a line break in your text, use the usual zsh means
  (Alt+Enter or `\` + Enter, depending on your setup).

## License

MIT, see [LICENSE](LICENSE).
