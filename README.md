# claude-cmd-deluxe (ccd)

A zsh plugin that turns text into a shell command, modifies an existing command, explains a command or fixes the previous one, through the Claude CLI (`claude -p`, Haiku by default). Nothing runs on its own: the command goes into your line and you press Enter yourself.

## Keys

| Key | What |
|---|---|
| `⌃G` | Generate 3 alternatives from the text on the line; the best one replaces the line. Modify an existing command with `command # instruction`. |
| `⌃G` (again) | Cycle through the 3 alternatives, locally, without a new call. |
| `⌃;` (Ghostty) / `⌃X e` | Explain the command on the line (empty line: the previous command): one sentence, then a table with a row per part, rendered in colour with [glow](https://github.com/charmbracelet/glow) under the line. A compound command (`&&`, `||`, `;`, `|`) gets a small table per step, with a line in between saying what the operator does and what output to expect. The line stays as it is, and you can keep typing. |
| `⌃X f` | Fix the previous command, with its exit status as context. Optionally type a hint first (e.g. the error message). |
| `⌃⇧;` (Ghostty) | Show the key overview. No model call. Elsewhere: run `claude-cmd-help`. |
| `⌃_` | Undo (standard zle undo). |

Ghostty sends `⌃;` and `⌃⇧;` as `ESC [ 59 ; 5 u` and `ESC [ 59 ; 6 u` (kitty keyboard protocol). Other terminals, such as Terminal.app, send nothing for them, so there the plugin uses `⌃X e` and has no help key. All keys are configurable.

Helper commands:

- `claude-cmd-help`: the key overview.
- `claude-cmd-prefs`: edit your preferences (through `chezmoi edit --apply` when chezmoi manages the file).
- `claude-cmd-context`: show exactly what context Claude receives.
- `claude-cmd-refresh`: refresh the cached list of installed Homebrew packages.

Every public function has a `#: description` line above it. If you have a `help` command that collects those lines from the files in a `HELP_SOURCES` array, declare the array (`typeset -ga HELP_SOURCES`) before loading the plugin and the plugin adds itself to it.

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
| `CLAUDE_CMD_PREFS` | `~/.config/claude-cmd/prefs.md` |
| `CLAUDE_CMD_CACHE` | `~/.cache/claude-cmd` (cached `brew leaves`, the last error message) |
| `CLAUDE_CMD_KEY_GEN` | `^G` |
| `CLAUDE_CMD_KEY_EXPLAIN` | `$'\e[59;5u'` (`⌃;`) in Ghostty, `^Xe` elsewhere |
| `CLAUDE_CMD_KEY_FIX` | `^Xf` |
| `CLAUDE_CMD_KEY_HELP` | `$'\e[59;6u'` (`⌃⇧;`) in Ghostty, empty (no key) elsewhere |
| `CLAUDE_CMD_CANDIDATES` | array of binaries to look for on `PATH` and mention as installed |

## How it works

- **Through `claude -p`, not the API.** Everything goes through the Claude CLI's own login or gateway config; no separate API key. Tools, MCP servers, slash commands and session history are switched off for these calls.
- **3 alternatives in one call.** Faster than asking again, because `claude -p` takes 1–3 seconds to start. The alternatives must differ meaningfully: another tool, another approach, or a safe variant.
- **Context per call:** your preferences file; installed tools (`brew leaves`, cached for at most 24 hours and refreshed in the background, plus the candidate list checked against `PATH`); OS, current directory and git branch. Deliberately left out: all of `PATH` (too large), aliases (they don't work outside your shell) and `--help` output (too heavy).
- **Long-form options where possible, never invented.** The prompt tells the model about BSD vs GNU tools on macOS.
- **Explanations as markdown.** The explain prompt asks for one sentence plus a table, or for a compound command a numbered table per step with an "I expect output like" line between them. `_cc_render` turns code fences without a language into `sh` fences and pipes the result through `glow`. It goes into the bottom area, in colour (see below).
- **Bottom area.** Everything the plugin shows (info bar with position `1/3`, label and keys; progress; errors; explanations; help) is drawn under the line through zle's `POSTDISPLAY`, and cleared when the line is accepted (`add-zle-hook-widget line-finish`, so other plugins' hooks keep working). zle prints escape codes in `POSTDISPLAY` literally, so `_cc_ansi_parse` splits glow's output into plain text and colour spans, which become `region_highlight` entries. Those are positioned from the start of the line, so a `line-pre-redraw` hook moves them along while you type. Only entries the plugin added are touched, so syntax highlighting keeps working.
- **Destructive commands** (`rm`, `--force`, `git reset --hard`, …) get a ⚠ line in the info bar.
- **Deliberately left out:** autosuggest while typing (too slow and too expensive through `claude -p`), chat mode, and capturing the output of the previous command.

## Tests

```sh
zsh tests/run.zsh
```

No framework needed, only zsh. `tests/bin/claude` is a fake Claude CLI that records its arguments and input and answers with fixtures, and `tests/glow-bin/glow` is a fake glow.

- `unit.test.zsh`: parsing, the destructive-command check, key labels, rendering, prompts, the call to `claude`, context, help.
- `settings.test.zsh`: default and overridden settings and key bindings, in and outside Ghostty.
- `widgets.test.zsh`: an interactive zsh in a pseudo-terminal (`zsh/zpty`), driven with real key presses. A probe key reads the line and the bottom area back.

GitHub Actions runs the suite on macOS, with real glow.

## Known limitations

- `⌃C` while waiting aborts the whole line.
- If your gateway doesn't know the `haiku` alias, set a full model ID in `CLAUDE_CMD_MODEL`.

## License

MIT
