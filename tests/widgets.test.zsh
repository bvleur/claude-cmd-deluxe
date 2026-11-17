# End-to-end tests: an interactive zsh in a pseudo-terminal (zsh/zpty), driven with real key presses.
# The line, the bottom area and region_highlight are read back through the ⌃T probe (pty_state); command
# output is read from the terminal output (pty_expect / pty_text).
source ${0:A:h}/lib.zsh

typeset -g CTRL_G=$'\a' CTRL_X_E=$'\x18e' CTRL_X_F=$'\x18f' ENTER=$'\r'
typeset -g GHOSTTY_CTRL_SEMI=$'\e[59;5u' GHOSTTY_CTRL_SHIFT_SEMI=$'\e[59;6u'

# Run a command line in the shell and wait for its output ($2) and the next prompt
run() { pty_reset; pty_send "$1$ENTER"; pty_expect "${2:-}*PROMPT> " }

test_case "⌃G turns text into the first alternative, with the info bar"
pty_start
pty_send "list files$CTRL_G"
assert_true "info bar not shown: $STATE_BOTTOM" pty_wait_bottom 'claude 1/3 · first label'
assert_eq 'echo ALT-$((100+1))' "$STATE_BUFFER"
assert_contains "$STATE_BOTTOM" '⌃G next'
stdin=$(<$CC_TEST_DIR/claude-stdin)
assert_contains "$stdin" '<context>'
assert_contains "$stdin" 'list files'
run '' 'ALT-101'
assert_contains "$(pty_text)" 'ALT-101'

test_case "⌃G again cycles through the alternatives, locally"
pty_start
pty_send "x$CTRL_G"; pty_wait_bottom 'claude 1/3'
rm -f $CC_TEST_DIR/claude-args
pty_send $CTRL_G
assert_true "no 2/3: $STATE_BOTTOM" pty_wait_bottom 'claude 2/3 · second label'
assert_eq 'echo ALT-$((100+2))' "$STATE_BUFFER"
pty_send $CTRL_G
assert_true "no 3/3: $STATE_BOTTOM" pty_wait_bottom 'claude 3/3 · third label'
pty_send $CTRL_G
assert_true "no wrap to 1/3: $STATE_BOTTOM" pty_wait_bottom 'claude 1/3'
assert_true "cycling called claude again" test ! -e $CC_TEST_DIR/claude-args

test_case "⌃G after editing the line asks claude again"
pty_start
pty_send "x$CTRL_G"; pty_wait_bottom 'claude 1/3'
rm -f $CC_TEST_DIR/claude-args
pty_send " # use printf$CTRL_G"
pty_wait_bottom 'claude 1/3'
sleep 0.3
assert_true "claude not called for the edited line" test -e $CC_TEST_DIR/claude-args
assert_contains "$(<$CC_TEST_DIR/claude-stdin)" 'echo ALT-$((100+1)) # use printf'

test_case "⌃G on an empty line asks for text and does not call claude"
pty_start
pty_send $CTRL_G
assert_true "no hint: $STATE_BOTTOM" pty_wait_bottom 'first type what you want to do'
assert_true "claude was called" test ! -e $CC_TEST_DIR/claude-args

test_case "a destructive alternative gets a warning"
print -r -- $'@@@ delete\nrm -rf build' >| $CC_TEST_DIR/answer
pty_start
pty_send "clean up$CTRL_G"
assert_true "no warning: $STATE_BOTTOM" pty_wait_bottom '⚠ destructive'
assert_eq 'rm -rf build' "$STATE_BUFFER"

test_case "a failing claude shows its error and leaves the line alone"
print -r -- 'boom' >| $CC_TEST_DIR/fail
pty_start
pty_send "x$CTRL_G"
assert_true "no error shown: $STATE_BOTTOM" pty_wait_bottom 'claude: no usable answer — boom'
assert_eq 'x' "$STATE_BUFFER"

test_case "⌃X e shows the explanation under the line and leaves the line alone"
pty_start
pty_send "echo \$((40+2))$CTRL_X_E"
assert_true "no explanation: $STATE_BOTTOM" pty_wait_bottom 'Prints the word hi'
assert_contains "$STATE_BOTTOM" '| Part | Meaning |'
assert_not_contains "$STATE_BOTTOM" 'explaining…' 'progress line still there'
assert_contains "$(<$CC_TEST_DIR/claude-stdin)" $'Command:\necho $((40+2))'
assert_eq 'echo $((40+2))' "$STATE_BUFFER"
run '' '42'

test_case "⌃X e on an empty line explains the previous command"
pty_start
run 'print -r -- PREV-$((1+1))' 'PREV-2'
pty_send $CTRL_X_E
assert_true "no explanation: $STATE_BOTTOM" pty_wait_bottom 'Prints the word hi'
assert_contains "$(<$CC_TEST_DIR/claude-stdin)" 'print -r -- PREV-$((1+1))'

test_case "⌃X f fixes the previous command with its exit status and the typed hint"
pty_start
run 'false'
pty_send "oops$CTRL_X_F"
assert_true "no alternative: $STATE_BOTTOM" pty_wait_bottom 'claude 1/3'
assert_eq 'echo ALT-$((100+1))' "$STATE_BUFFER"
stdin=$(<$CC_TEST_DIR/claude-stdin)
assert_contains "$stdin" $'(exit status 1):\nfalse'
assert_contains "$stdin" 'User hint about what went wrong: oops'

test_case "the bottom area is cleared when the line is accepted"
pty_start
pty_send "x$CTRL_G"; pty_wait_bottom 'claude 1/3'
run '' 'ALT-101'
pty_state
assert_eq '' "$STATE_BOTTOM"

test_case "Ghostty: ⌃; explains, ⌃⇧; shows the key overview"
pty_start TERM_PROGRAM=ghostty
pty_send "echo hi$GHOSTTY_CTRL_SEMI"
assert_true "⌃; did not explain: $STATE_BOTTOM" pty_wait_bottom 'Prints the word hi'
pty_send $GHOSTTY_CTRL_SHIFT_SEMI
assert_true "⌃⇧; did not show help: $STATE_BOTTOM" pty_wait_bottom '| Key | What |'
assert_contains "$STATE_BOTTOM" '| `⌃⇧;` | This overview. |'
assert_contains "$STATE_BOTTOM" '| `⌃;` | Explain'
assert_eq 'echo hi' "$STATE_BUFFER"

test_case "explanations go through glow when it is installed"
pty_start PATH="$CC_ROOT/tests/glow-bin:$PATH"
pty_send "echo hi$CTRL_X_E"
assert_true "glow not used: $STATE_BOTTOM" pty_wait_bottom 'GLOW-ARGS: -w='
assert_contains "$STATE_BOTTOM" '-s=dark -'

test_case "colours from glow become highlights that move along when you type"
pty_start PATH="$CC_ROOT/tests/glow-ansi-bin:$PATH"
pty_send "echo hi$CTRL_X_E"
assert_true "no explanation: $STATE_BOTTOM" pty_wait_bottom 'Explained: Prints the word hi'
assert_not_contains "$STATE_BOTTOM" $'\e' 'escape codes in the bottom area'
# BUFFER "echo hi" is 7 characters, the bottom area starts with a newline: "Explained" is at 8..17
assert_contains "|$STATE_HL|" '|8 17 fg=203,bold|'
pty_send " there"
pty_state
assert_eq 'echo hi there' "$STATE_BUFFER"
assert_contains "$STATE_BOTTOM" 'Explained: Prints the word hi' 'explanation gone while typing'
assert_contains "|$STATE_HL|" '|14 23 fg=203,bold|' 'highlight did not move along'
assert_not_contains "|$STATE_HL|" '|8 17 ' 'old highlight left behind'
run '' 'hi there'
pty_state
assert_eq '' "$STATE_BOTTOM"
assert_not_contains "$STATE_HL" 'fg=203' 'highlight left after the line was accepted'

finish
