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
assert_true "info bar not shown: $STATE_BOTTOM" pty_wait_bottom 'ccd 1/3 · first label'
assert_eq 'echo ALT-$((100+1))' "$STATE_BUFFER"
assert_contains "$STATE_BOTTOM" '⌃G next'
stdin=$(<$CC_TEST_DIR/claude-stdin)
assert_contains "$stdin" '<context>'
assert_contains "$stdin" 'list files'
run '' 'ALT-101'
assert_contains "$(pty_text)" 'ALT-101'

test_case "⌃G again cycles through the alternatives, locally"
pty_start
pty_send "x$CTRL_G"; pty_wait_bottom 'ccd 1/3'
rm -f $CC_TEST_DIR/claude-args
pty_send $CTRL_G
assert_true "no 2/3: $STATE_BOTTOM" pty_wait_bottom 'ccd 2/3 · second label'
assert_eq 'echo ALT-$((100+2))' "$STATE_BUFFER"
pty_send $CTRL_G
assert_true "no 3/3: $STATE_BOTTOM" pty_wait_bottom 'ccd 3/3 · third label'
pty_send $CTRL_G
assert_true "no wrap to 1/3: $STATE_BOTTOM" pty_wait_bottom 'ccd 1/3'
assert_true "cycling called claude again" test ! -e $CC_TEST_DIR/claude-args

test_case "⌃G after editing the line asks claude again"
pty_start
pty_send "x$CTRL_G"; pty_wait_bottom 'ccd 1/3'
rm -f $CC_TEST_DIR/claude-args
pty_send " # use printf$CTRL_G"
pty_wait_bottom 'ccd 1/3'
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
assert_true "no error shown: $STATE_BOTTOM" pty_wait_bottom 'ccd: no usable answer — boom'
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
assert_true "no alternative: $STATE_BOTTOM" pty_wait_bottom 'ccd 1/3'
assert_eq 'echo ALT-$((100+1))' "$STATE_BUFFER"
stdin=$(<$CC_TEST_DIR/claude-stdin)
assert_contains "$stdin" $'(exit status 1):\nfalse'
assert_contains "$stdin" 'User hint about what went wrong: oops'

test_case "the bottom area is cleared when the line is accepted"
pty_start
pty_send "x$CTRL_G"; pty_wait_bottom 'ccd 1/3'
run '' 'ALT-101'
pty_state
assert_eq '' "$STATE_BOTTOM"

test_case "Ghostty: ⌃; generates and cycles"
pty_start TERM_PROGRAM=ghostty
pty_send "list files$GHOSTTY_CTRL_SEMI"
assert_true "no info bar: $STATE_BOTTOM" pty_wait_bottom 'ccd 1/3 · first label'
assert_contains "$STATE_BOTTOM" '⌃; next   ⌃⇧; menu'
pty_send $GHOSTTY_CTRL_SEMI
assert_true "no 2/3: $STATE_BOTTOM" pty_wait_bottom 'ccd 2/3'

test_case "Ghostty: ⌃⇧; shows the menu, e explains"
pty_start TERM_PROGRAM=ghostty
pty_send "echo hi$GHOSTTY_CTRL_SHIFT_SEMI"
assert_true "no menu: $STATE_BOTTOM" pty_expect '*pick one*'
pty_send e
assert_true "e did not explain: $STATE_BOTTOM" pty_wait_bottom 'Prints the word hi'
assert_eq 'echo hi' "$STATE_BUFFER"

test_case "Ghostty: ⌃⇧; h shows the overview, another key just closes the menu"
pty_start TERM_PROGRAM=ghostty
pty_send "echo hi$GHOSTTY_CTRL_SHIFT_SEMI"; pty_expect '*pick one*'
pty_send h
assert_true "h did not show help: $STATE_BOTTOM" pty_wait_bottom '| Key | What |'
assert_contains "$STATE_BOTTOM" '| `⌃⇧;` `e` | Explain'
assert_eq 'echo hi' "$STATE_BUFFER"
pty_send "$GHOSTTY_CTRL_SHIFT_SEMI"; pty_expect '*pick one*'
pty_send x
pty_state
assert_eq 'echo hi' "$STATE_BUFFER" 'the closing key was typed into the line'
assert_eq '' "$STATE_BOTTOM" 'menu still shown'

test_case "Ghostty: ⌃: (how Ghostty may send ⌃⇧;) opens the menu too"
pty_start TERM_PROGRAM=ghostty
pty_send $'echo hi\e[58;5u'
assert_true "no menu" pty_expect '*pick one*'
pty_send x

test_case "Ghostty: ⌃⇧; c runs ccd-context and gives the line back"
pty_start TERM_PROGRAM=ghostty
pty_send "echo hi$GHOSTTY_CTRL_SHIFT_SEMI"; pty_expect '*pick one*'
pty_reset
pty_send c
assert_true "context not printed" pty_expect '*User preferences:*PROMPT> '
pty_state
assert_eq 'echo hi' "$STATE_BUFFER" 'line not given back'

test_case "Ghostty: a long explanation is cut off with a pointer to ⌃⇧; E, which pages it without a new call"
pty_start TERM_PROGRAM=ghostty PAGER=cat
print -rl -- "Long one." "" row\ {1..60} >| $CC_TEST_DIR/answer
pty_send "echo hi$GHOSTTY_CTRL_SHIFT_SEMI"; pty_expect '*pick one*'
pty_send e
assert_true "no cut-off hint: $STATE_BOTTOM" pty_wait_bottom 'more lines: ⌃⇧; E for the full explanation'
assert_contains "$STATE_BOTTOM" 'row 1'
assert_not_contains "$STATE_BOTTOM" 'row 60'
rm -f $CC_TEST_DIR/claude-args
pty_reset
pty_send "$GHOSTTY_CTRL_SHIFT_SEMI"; pty_expect '*pick one*'
pty_send E
assert_true "pager did not show the whole explanation" pty_expect "*row 60*"
assert_true "the explanation was asked again" test ! -e $CC_TEST_DIR/claude-args
pty_state
assert_eq 'echo hi' "$STATE_BUFFER"
rm -f $CC_TEST_DIR/answer

test_case "ccd-page: the last explanation, or a message when there is none"
pty_start
run ccd-page 'no explanation yet'

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
# BUFFER "echo hi" is 7 characters, the bottom area starts with two newlines: "Explained" is at 9..18
assert_contains "|$STATE_HL|" '|9 18 fg=203,bold|'
assert_contains "$STATE_HL" '9 ' 'no base colour'
assert_true "base colour comes before glow's colour" eval '[[ $STATE_HL == *"fg=244"*"fg=203,bold"* ]]'
pty_send " there"
pty_state
assert_eq 'echo hi there' "$STATE_BUFFER"
assert_contains "$STATE_BOTTOM" 'Explained: Prints the word hi' 'explanation gone while typing'
assert_contains "|$STATE_HL|" '|15 24 fg=203,bold|' 'highlight did not move along'
assert_not_contains "|$STATE_HL|" '|9 18 ' 'old highlight left behind'
run '' 'hi there'
pty_state
assert_eq '' "$STATE_BOTTOM"
assert_not_contains "$STATE_HL" 'fg=203' 'highlight left after the line was accepted'
assert_not_contains "$STATE_HL" 'fg=244' 'base colour left after the line was accepted'

test_case "while claude thinks, the bottom area shows claude-cmd-deluxe, then it gives way to the answer"
print -r -- 2 >| $CC_TEST_DIR/delay
pty_start
pty_send "list files$CTRL_G"
assert_true "no busy line" pty_expect '*claude-cmd-*thinking…*'
assert_contains "$CC_PTY_OUT" $'\e[1m\e[38;' "deluxe not coloured"
assert_true "no answer after the delay: $STATE_BOTTOM" pty_wait_bottom 'ccd 1/3 · first label'
assert_not_contains "$STATE_BOTTOM" 'thinking' 'busy line left behind'

test_case "⌃C while claude thinks clears the animation and stops claude"
print -r -- 30 >| $CC_TEST_DIR/delay
pty_start
pty_send "list files$CTRL_G"
assert_true "no busy line" pty_expect '*claude-cmd-*thinking…*'
until [[ -s $CC_TEST_DIR/claude-pid ]]; do sleep 0.05; done
pid=$(<$CC_TEST_DIR/claude-pid)
pty_send $'\x03'
sleep 0.5
pty_state
assert_eq '' "$STATE_BOTTOM" 'animation left behind after ⌃C'
gone() { local -F d=$(( EPOCHREALTIME + 3 )); while kill -0 $1 2>/dev/null; do (( EPOCHREALTIME > d )) && return 1; sleep 0.05; done }
assert_true "claude still running after ⌃C" gone $pid

finish
