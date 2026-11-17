# Tests for the settings and key bindings the plugin sets up when it is loaded.
source ${0:A:h}/lib.zsh

load() { zsh -f -c "export TERM_PROGRAM=${(q)1}; $2; source ${(q)CC_PLUGIN}; $3" 2>&1 }

test_case "keys outside Ghostty"
out=$(load '' '' 'bindkey "^G"; bindkey "^Xe"; bindkey "^Xf"; print -r -- "HELP=[$CLAUDE_CMD_KEY_HELP]"')
assert_contains "$out" '"^G" claude-cmd-generate'
assert_contains "$out" '"^Xe" claude-cmd-explain'
assert_contains "$out" '"^Xf" claude-cmd-fix'
assert_contains "$out" 'HELP=[]'

test_case "keys in Ghostty: ⌃; explains, ⌃⇧; shows help"
out=$(load ghostty '' 'bindkey "^[[59;5u"; bindkey "^[[59;6u"; bindkey "^Xe"')
assert_contains "$out" '"^[[59;5u" claude-cmd-explain'
assert_contains "$out" '"^[[59;6u" claude-cmd-help-widget'
assert_not_contains "$out" '"^Xe" claude-cmd-explain' 'in Ghostty ⌃X e should keep its default binding'

test_case "settings set before loading win"
out=$(load ghostty 'CLAUDE_CMD_KEY_EXPLAIN="^Xx"; CLAUDE_CMD_MODEL=sonnet; CLAUDE_CMD_LANG=Dutch' \
  'bindkey "^Xx"; print -r -- "$CLAUDE_CMD_MODEL $CLAUDE_CMD_LANG"')
assert_contains "$out" '"^Xx" claude-cmd-explain'
assert_contains "$out" 'sonnet Dutch'

test_case "defaults"
out=$(load '' '' 'print -r -- "$CLAUDE_CMD_MODEL $CLAUDE_CMD_LANG $CLAUDE_CMD_GLOW_STYLE"')
assert_eq 'haiku English dark' "$out"

test_case "the plugin adds itself to HELP_SOURCES only when that array exists"
out=$(load '' 'typeset -ga HELP_SOURCES=(/x.zsh)' 'print -rl -- $HELP_SOURCES')
assert_eq "/x.zsh
${CC_PLUGIN:A}" "$out"
out=$(load '' '' 'print -r -- "SET=${+HELP_SOURCES}"')
assert_eq 'SET=0' "$out"

test_case "without claude on PATH the plugin does nothing"
out=$(PATH=/usr/bin:/bin; load '' '' 'print -r -- "W=${+functions[claude-cmd-generate]}"; bindkey "^G"')
assert_contains "$out" 'W=0'
assert_not_contains "$out" 'claude-cmd-generate'

finish
