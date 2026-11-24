# claude-cmd-deluxe (ccd)

A zsh plugin that turns text into a shell command, modifies an existing command, explains a command or fixes the previous one, through the Claude CLI (`claude -p`, Haiku by default). Nothing runs on its own: the command goes into your line and you press Enter yourself.

## Keys

In [Ghostty](https://ghostty.org) all of ccd sits on two keys:

| Key | What |
|---|---|
| `⌃;` | Generate 3 alternatives from the text on the line; the best one replaces the line. Modify an existing command with `command # instruction`. |
| `⌃;` (again) | Cycle through the 3 alternatives, locally, without a new call. |
| `⌃⇧;` | Menu: the options appear under the line, the next key picks one. Any other key closes it. |
| `⌃⇧;` `e` | Explain the command on the line (empty line: the previous command): one sentence, then a table with a row per part, rendered in colour with [glow](https://github.com/charmbracelet/glow) under the line. A compound command (`&&`, `\|\|`, `;`, `\|`) gets a small table per step, with a line in between saying what the operator does and what output to expect. The line stays as it is, and you can keep typing. |
| `⌃⇧;` `E` | The same explanation in a pager (`$PAGER`, default `less -R`), to scroll through a long one. Reuses the last explanation of the same command, without a new call. An inline explanation taller than the screen is cut off with a line pointing here. |
| `⌃⇧;` `f` | Fix the previous command, with its exit status as context. Optionally type a hint first (e.g. the error message). |
| `⌃⇧;` `h` | All keys and commands. No model call. |
| `⌃⇧;` `p` / `c` / `r` | Run `ccd-prefs`, `ccd-context` or `ccd-refresh`; your line comes back afterwards. |

Ghostty sends `⌃;` and `⌃⇧;` as `ESC [ 59 ; 5 u` and `ESC [ 59 ; 6 u` (kitty keyboard protocol). Because `⌃⇧;` types `:` on most layouts, the plugin also binds the spellings of `⌃:` for the menu. Other terminals, such as Terminal.app, send nothing for these keys, so there the plugin falls back to:

| Key | What |
|---|---|
| `⌃G` | Generate; again: next alternative. |
| `⌃X e` | Explain. |
| `⌃X f` | Fix the previous command. |

`⌃_` undoes (standard zle undo). All keys are configurable.

Helper commands:

- `ccd-help`: all keys and commands.
- `ccd-prefs`: edit your preferences (through `chezmoi edit --apply` when chezmoi manages the file).
- `ccd-page`: the last explanation in a pager (the way to scroll outside Ghostty).
- `ccd-context`: show exactly what context Claude receives.
- `ccd-refresh`: refresh the cached list of installed Homebrew packages.
- `ccd-last`: print the log of the last `claude` call (exit status, stderr, the raw answer). The error line under the prompt ends with `(details: ccd-last)` when a call gave no usable answer.

Every public function has a `#: [ccd] description` line above it (`[ccd, more]` for the ones you rarely type). If you have a `help` command that collects those lines from the files in a `HELP_SOURCES` array, declare the array (`typeset -ga HELP_SOURCES`) before loading the plugin and the plugin adds itself to it.

## Install

Requirements: zsh, the [Claude CLI](https://docs.claude.com/en/docs/claude-code) (`claude`) on `PATH`, and optionally `glow` for coloured explanations. Without `claude` the plugin does nothing; without `glow` explanations are printed as plain markdown.

With [antidote](https://github.com/mattmc3/antidote), add this line to `.zsh_plugins.txt`, after your other plugins so these key bindings win:

```
bvleur/claude-cmd-deluxe
```

By hand:

```sh
git clone https://github.com/bvleur/claude-cmd-deluxe ~/.local/share/claude-cmd-deluxe
print 'source ~/.local/share/claude-cmd-deluxe/claude-cmd-deluxe.plugin.zsh' >> ~/.zshrc
```

Optionally copy [`prefs.example.md`](prefs.example.md) to `~/.config/claude-cmd/prefs.md` and adapt it: it tells Claude which tools you prefer and how you like your options.

## Settings

Set these before the plugin is loaded.

| Variable | Default |
|---|---|
| `CLAUDE_CMD_MODEL` | `haiku` |
| `CLAUDE_CMD_LANG` | `English` (language of explanations and alternative labels) |
| `CLAUDE_CMD_GLOW_STYLE` | `dark` |
| `CLAUDE_CMD_BOTTOM_STYLE` | `fg=244` (grey): base colour of everything under the line, as a `region_highlight` spec; empty for the terminal's default |
| `CLAUDE_CMD_PREFS` | `~/.config/claude-cmd/prefs.md` |
| `CLAUDE_CMD_CACHE` | `~/.cache/claude-cmd` (cached `brew leaves`, `last-call.log` with the last claude call) |
| `CLAUDE_CMD_KEY_GEN` | `$'\e[59;5u'` (`⌃;`) in Ghostty, `^G` elsewhere |
| `CLAUDE_CMD_KEY_MENU` | `$'\e[59;6u'` (`⌃⇧;`) in Ghostty, empty (no menu) elsewhere |
| `CLAUDE_CMD_KEY_EXPLAIN` | empty in Ghostty (use the menu), `^Xe` elsewhere |
| `CLAUDE_CMD_KEY_FIX` | empty in Ghostty (use the menu), `^Xf` elsewhere |
| `CLAUDE_CMD_CANDIDATES` | array of binaries to look for on `PATH` and mention as installed |

## How it works

- **Through `claude -p`, not the API.** Everything goes through the Claude CLI's own login or gateway config; no separate API key. Tools, MCP servers, slash commands and session history are switched off for these calls.
- **3 alternatives in one call.** Faster than asking again, because `claude -p` takes 1–3 seconds to start. The alternatives must differ meaningfully: another tool, another approach, or a safe variant.
- **Context per call:** your preferences file; installed tools (`brew leaves`, cached for at most 24 hours and refreshed in the background, plus the candidate list checked against `PATH`); OS, current directory and git branch. Deliberately left out: all of `PATH` (too large), aliases (they don't work outside your shell) and `--help` output (too heavy).
- **Long-form options where possible, never invented.** The prompt tells the model about BSD vs GNU tools on macOS.
- **Explanations as markdown.** The explain prompt asks for one sentence plus a table, or for a compound command a numbered table per step with an "I expect output like" line between them. `_cc_render` turns code fences without a language into `sh` fences and pipes the result through `glow`. It goes into the bottom area, in colour (see below).
- **Bottom area.** Everything the plugin shows (info bar with position `1/3`, label and keys; progress; errors; explanations; help) is drawn under the line through zle's `POSTDISPLAY`, after a blank line and in grey (glow's colours on top), and cleared when the line is accepted (`add-zle-hook-widget line-finish`, so other plugins' hooks keep working). zle prints escape codes in `POSTDISPLAY` literally, so `_cc_ansi_parse` splits glow's output into plain text and colour spans, which become `region_highlight` entries. Those are positioned from the start of the line, so a `line-pre-redraw` hook moves them along while you type. Only entries the plugin added are touched, so syntax highlighting keeps working.
- **Destructive commands** (`rm`, `--force`, `git reset --hard`, …) get a ⚠ line in the info bar.
- **Deliberately left out:** autosuggest while typing (too slow and too expensive through `claude -p`), chat mode, and capturing the output of the previous command.

## Tests

```sh
mise run test
```

`mise tasks` lists the other tasks. Without mise, `zsh tests/run.zsh` does the same: no framework needed, only zsh. `tests/bin/claude` is a fake Claude CLI that records its arguments and input and answers with fixtures, and `tests/glow-bin/glow` is a fake glow.

- `unit.test.zsh`: parsing, the destructive-command check, key labels, rendering, prompts, the call to `claude`, context, help.
- `settings.test.zsh`: default and overridden settings and key bindings, in and outside Ghostty.
- `widgets.test.zsh`: an interactive zsh in a pseudo-terminal (`zsh/zpty`), driven with real key presses. A probe key reads the line and the bottom area back.

GitHub Actions runs `mise run ci` on macOS, with the real glow pinned in `mise.toml`.

## Known limitations

- `⌃C` while waiting aborts the whole line (the busy animation is cleared and claude is stopped).
- While waiting, keys you type are queued and handled once the answer is in; the animation needs `zsh/zselect` (falls back to `sleep`) and uses 24-bit colour, mapped to 256 colours on terminals without truecolor. `NO_COLOR` turns the sweep off.
- If your gateway doesn't know the `haiku` alias, set a full model ID in `CLAUDE_CMD_MODEL`.

## License

MIT
