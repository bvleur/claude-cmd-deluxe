# Tests for the settings and key bindings the plugin sets up when it is loaded.
source ${0:A:h}/lib.zsh

load() { zsh -f -c "export TERM_PROGRAM=${(q)1}; $2; source ${(q)CC_PLUGIN}; $3" 2>&1 }

test_case "keys outside Ghostty"
out=$(load '' '' 'bindkey "^G"; bindkey "^Xe"; bindkey "^Xf"; print -r -- "MENU=[$CLAUDE_CMD_KEY_MENU]"')
assert_contains "$out" '"^G" ccd-generate'
assert_contains "$out" '"^Xe" ccd-explain'
assert_contains "$out" '"^Xf" ccd-fix'
assert_contains "$out" 'MENU=[]'

test_case "keys in Ghostty: only ⌃; (generate) and ⌃⇧; (menu)"
out=$(load ghostty '' 'bindkey "^[[59;5u"; bindkey "^[[59;6u"; bindkey "^G"; bindkey "^Xe"; bindkey "^Xf"')
assert_contains "$out" '"^[[59;5u" ccd-generate'
assert_contains "$out" '"^[[59;6u" ccd-menu'
assert_not_contains "$out" 'ccd-explain' 'in Ghostty ⌃X e keeps its default binding'
assert_not_contains "$out" 'ccd-fix' 'in Ghostty ⌃X f keeps its default binding'
assert_not_contains "$out" '"^G" ccd-generate' 'in Ghostty ⌃G keeps its default binding'
out=$(load ghostty '' 'bindkey "^[[58;5u"; bindkey "^[[58;6u"')
assert_contains "$out" '"^[[58;5u" ccd-menu' 'Ghostty may report ⌃⇧; as ⌃:'
assert_contains "$out" '"^[[58;6u" ccd-menu'
out=$(load ghostty 'CLAUDE_CMD_KEY_MENU="^Xm"' 'bindkey "^Xm"; bindkey "^[[58;5u"')
assert_contains "$out" '"^Xm" ccd-menu'
assert_not_contains "$out" '"^[[58;5u" ccd-menu' 'the ⌃: spellings only come with the default menu key'

test_case "settings set before loading win"
out=$(load ghostty 'CLAUDE_CMD_KEY_EXPLAIN="^Xx"; CLAUDE_CMD_MODEL=sonnet; CLAUDE_CMD_LANG=Dutch' \
  'bindkey "^Xx"; print -r -- "$CLAUDE_CMD_MODEL $CLAUDE_CMD_LANG"')
assert_contains "$out" '"^Xx" ccd-explain'
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
out=$(PATH=/usr/bin:/bin; load '' '' 'print -r -- "W=${+functions[ccd-generate]}"; bindkey "^G"')
assert_contains "$out" 'W=0'
assert_not_contains "$out" 'ccd-generate'

finish
