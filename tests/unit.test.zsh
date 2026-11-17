# Unit tests for the plugin's helper functions (no terminal needed).
source ${0:A:h}/lib.zsh
source $CC_PLUGIN

# ── parsing the model's answer ────────────────────────────────────────────────

test_case "parse: three labelled alternatives"
_cc_parse $'@@@ list all\nls -la\n@@@ only dirs\nls -d */\n@@@ tree\neza --tree'
assert_eq 3 ${#_cc_alts}
assert_eq 'ls -la' "${_cc_alts[1]}"
assert_eq 'eza --tree' "${_cc_alts[3]}"
assert_eq 'only dirs' "${_cc_labels[2]}"

test_case "parse: code fences are dropped"
_cc_parse $'@@@ one\n```sh\nls\n```\n@@@ two\n```\npwd\n```'
assert_eq 'ls' "${_cc_alts[1]}"
assert_eq 'pwd' "${_cc_alts[2]}"

test_case "parse: multi-line command is kept together"
_cc_parse $'@@@ loop\nfor f in *; do\n  echo $f\ndone'
assert_eq 1 ${#_cc_alts}
assert_eq $'for f in *; do\n  echo $f\ndone' "${_cc_alts[1]}"

test_case "parse: answer without the format becomes one alternative"
_cc_parse $'```\nls -la\n```'
assert_eq 1 ${#_cc_alts}
assert_eq 'ls -la' "${_cc_alts[1]}"
assert_eq '' "${_cc_labels[1]}"

test_case "parse: empty answer gives no alternatives"
_cc_parse ''
assert_eq 0 ${#_cc_alts}

# ── destructive-command warning ───────────────────────────────────────────────

test_case "destructive: dangerous commands are flagged"
for cmd in 'rm -rf build' 'sudo rm foo' 'git reset --hard HEAD~1' 'git push --force' 'find . -name x -delete' \
           'chmod -R 777 .' 'git clean -fdx' 'echo x | xargs rm' 'kill 123' '  rm foo' 'ls && rm foo' \
           'fd -e tmp | xargs -0 rm' '(cd /tmp; rm x)'; do
  assert_true "not flagged: $cmd" _cc_is_destructive "$cmd"
done

test_case "destructive: harmless commands are not flagged"
for cmd in 'ls -la' 'git status' 'rg --ignore-case foo' 'echo rm' 'git push' 'cat format.txt' \
           'man rm' 'rg kill src' 'echo "dd it"'; do
  assert_true "flagged: $cmd" eval '! _cc_is_destructive "$cmd"'
done

# ── key labels ────────────────────────────────────────────────────────────────

test_case "key labels"
assert_eq '⌃G'   "$(_cc_keylabel '^G')"
assert_eq '⌃X e' "$(_cc_keylabel '^Xe')"
assert_eq '⌥F'   "$(_cc_keylabel '^[f')"
assert_eq '⌃;'   "$(_cc_keylabel $'\e[59;5u')"
assert_eq '⌃⇧;'  "$(_cc_keylabel $'\e[59;6u')"
assert_eq '⌃⇧;'  "$(_cc_keylabel $'\e[58;5u')" 'Ghostty can report ⌃⇧; as ⌃:'

# ── markdown rendering ────────────────────────────────────────────────────────

test_case "render: without glow the markdown is printed, untagged fences become sh"
out=$(print -r -- $'text\n```\nls -la\n```\n```bash\necho hi\n```\n```\npwd\n```' | _cc_render)
assert_eq $'text\n```sh\nls -la\n```\n```bash\necho hi\n```\n```sh\npwd\n```' "$out"

test_case "render: indented and closing fences are left alone"
out=$(print -r -- $'  ```\nx\n  ```' | _cc_render)
assert_eq $'  ```sh\nx\n  ```' "$out"

test_case "render: glow gets forced colour, the width and the style"
out=$(PATH="$CC_ROOT/tests/glow-bin:$PATH" COLUMNS=99 CLAUDE_CMD_GLOW_STYLE=light; print -r -- $'```\nls\n```' | _cc_render)
assert_contains "$out" 'GLOW-ARGS: -w=99 -s=light -'
assert_contains "$out" 'GLOW-COLOR: 1'
assert_contains "$out" '```sh'

test_case "render: real glow colours a table (skipped when glow is not installed)"
if [[ -n $CC_REAL_GLOW ]]; then
  out=$(PATH="${CC_REAL_GLOW:h}:$PATH"; print -r -- $'Sum.\n\n| Part | Meaning |\n|---|---|\n| `ls` | lists |\n\n```\nls -la\n```' | _cc_render)
  assert_contains "$out" $'\e[' 'no colour codes'
  assert_contains "$out" 'Meaning'
  assert_not_contains "$out" '```' 'fences were not rendered'
else
  print -r -- "  - skipped: glow not installed"
fi

# ── colour codes → plain text + region_highlight spans ───────────────────────

test_case "ansi: 256 colours, background, bold and reset become spans"
_cc_ansi_parse $'\e[38;5;252mHi \e[1;38;5;203;48;5;236m ls \e[0m done'
assert_eq 'Hi  ls  done' "$REPLY"
assert_eq '0 3 fg=252|3 7 fg=203,bg=236,bold' "${(j:|:)reply}"

test_case "ansi: basic, bright and true colours, underline, bare reset"
_cc_ansi_parse $'\e[31ma\e[m\e[92mb\e[0m\e[38;2;255;0;16mc\e[0m\e[4md\e[24me'
assert_eq 'abcde' "$REPLY"
assert_eq '0 1 fg=1|1 2 fg=10|2 3 fg=#ff0010|3 4 underline' "${(j:|:)reply}"

test_case "ansi: other escape sequences are dropped, hyperlinks keep their text"
_cc_ansi_parse $'a\e[2Kb\e]8;;https://x\e\\link\e]8;;\e\\c'
assert_eq 'ablinkc' "$REPLY"
assert_eq 0 ${#reply}

test_case "ansi: offsets count characters, not bytes"
_cc_ansi_parse $'✦ é\e[31mü\e[0m'
assert_eq '✦ éü' "$REPLY"
assert_eq '3 4 fg=1' "${(j:|:)reply}"

test_case "ansi: plain text has no spans"
_cc_ansi_parse 'plain text'
assert_eq 'plain text' "$REPLY"
assert_eq 0 ${#reply}

# ── prompts and the call to claude ────────────────────────────────────────────

test_case "explain prompt: tables in the configured language, one per step of a compound command"
p=$(CLAUDE_CMD_LANG=Dutch; _cc_sys_explain)
assert_contains "$p" 'in Dutch'
assert_contains "$p" 'into Dutch'
assert_contains "$p" 'split it into steps at every &&, ||, ; and |'
assert_contains "$p" 'Operators never get a row.'
assert_contains "$p" "'I expect output like:'"
assert_contains "$p" '```text'
assert_contains "$p" 'no nested lists, no arrows'
assert_contains "$p" 'as \| so it'
assert_contains "$p" '```sh'

test_case "commands prompt asks for exactly three alternatives"
assert_contains "$(_cc_sys_commands)" 'Output EXACTLY 3 alternatives'

test_case "call: model, system prompt and message reach claude"
out=$(CLAUDE_CMD_MODEL=test-model; _cc_call 'SYSTEM PROMPT' 'the message')
args=$(<$CC_TEST_DIR/claude-args)
assert_contains "$args" $'--model\ntest-model'
assert_contains "$args" $'--system-prompt\nSYSTEM PROMPT'
assert_contains "$args" $'--tools\n\n'
assert_contains "$args" '--no-session-persistence'
assert_eq 'the message' "$(<$CC_TEST_DIR/claude-stdin)"

test_case "call: stderr is kept for the error message"
print -r -- 'gateway said no' >| $CC_TEST_DIR/fail
out=$(_cc_call x y)
assert_eq '' "$out"
assert_eq 'ccd: no usable answer — gateway said no' "$(_cc_error_msg)"

# ── context ───────────────────────────────────────────────────────────────────

test_case "context: preferences file is included, or (none)"
assert_contains "$(_cc_context)" $'User preferences:\n(none)'
mkdir -p ${CLAUDE_CMD_PREFS:h}
print -r -- 'Use rg, not grep' >| $CLAUDE_CMD_PREFS
assert_contains "$(_cc_context)" 'Use rg, not grep'
assert_contains "$(_cc_context)" "Current directory: $PWD"

# ── help ──────────────────────────────────────────────────────────────────────

test_case "help: lists the configured keys, without menu rows when there is no menu key"
out=$(ccd-help)
assert_contains "$out" '| `⌃G` | Turn the text'
assert_contains "$out" '| `⌃X e` | Explain'
assert_contains "$out" '| `⌃X f` | Fix'
assert_not_contains "$out" 'Menu'
assert_contains "$out" 'Commands: `ccd-help`, `ccd-prefs`'

test_case "help: with a menu key, a row per menu option and no direct explain/fix rows when unset"
out=$(CLAUDE_CMD_KEY_GEN=$'\e[59;5u' CLAUDE_CMD_KEY_MENU=$'\e[59;6u' CLAUDE_CMD_KEY_EXPLAIN= CLAUDE_CMD_KEY_FIX= ccd-help)
assert_contains "$out" '| `⌃;` | Turn the text'
assert_contains "$out" '| `⌃⇧;` | Menu'
assert_contains "$out" '| `⌃⇧;` `e` | Explain the command'
assert_contains "$out" '| `⌃⇧;` `f` | Fix the previous command'
assert_contains "$out" '| `⌃⇧;` `h` | All keys and commands. |'
assert_not_contains "$out" '⌃X'

test_case "menu text: one line per option"
out=$(_cc_menu_text)
assert_contains "$out" 'ccd ─ pick one'
assert_contains "$out" $'\n  e  explain the command'
assert_contains "$out" $'\n  r  refresh the list'

test_case "info bar hints: only keys that are bound"
assert_eq '⌃G generate   ⌃X e explain   ⌃X f fix previous   ⌃_ undo' "$(_cc_hints)"
assert_eq '⌃; next   ⌃⇧; menu   ⌃_ undo' "$(CLAUDE_CMD_KEY_GEN=$'\e[59;5u' CLAUDE_CMD_KEY_MENU=$'\e[59;6u' CLAUDE_CMD_KEY_EXPLAIN= CLAUDE_CMD_KEY_FIX= _cc_hints next)"

test_case "#: lines carry a [ccd] category for a help command"
assert_eq 0 "$(grep -A1 '^#:' $CC_PLUGIN | grep -c '^#: [^[]')" 'a #: line without a category'

finish
