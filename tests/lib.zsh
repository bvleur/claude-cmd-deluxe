# Shared test helpers. Each *.test.zsh file sources this and runs in its own `zsh -f`.
emulate -L zsh
setopt typeset_silent

typeset -g CC_ROOT=${${(%):-%x}:A:h:h}
typeset -g CC_PLUGIN=$CC_ROOT/claude-cmd-deluxe.plugin.zsh
typeset -g CC_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-cmd-test.XXXXXX")
typeset -gi CC_FAILS=0 CC_PASSES=0
typeset -g  CC_CURRENT=""

# The real glow, if installed, for the one smoke test that uses it
typeset -g CC_REAL_GLOW=${commands[glow]:-}

# Isolated environment: fake claude first on PATH, no real glow, throwaway config/cache dirs.
export CC_TEST_DIR
export PATH="$CC_ROOT/tests/bin:/usr/bin:/bin"
export XDG_CONFIG_HOME=$CC_TEST_DIR/config XDG_CACHE_HOME=$CC_TEST_DIR/cache
unset TERM_PROGRAM CLAUDE_CMD_KEY_EXPLAIN CLAUDE_CMD_KEY_MENU CLAUDE_CMD_KEY_GEN CLAUDE_CMD_KEY_FIX
mkdir -p $XDG_CONFIG_HOME $XDG_CACHE_HOME

zmodload zsh/datetime zsh/zpty

# zle only draws multibyte characters (✦ ⌃ │) under a UTF-8 locale
typeset -g CC_LOCALE
for CC_LOCALE in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  [[ -n ${(M)${(f)"$(locale -a 2>/dev/null)"}:#$CC_LOCALE} ]] && break
done
export LANG=$CC_LOCALE LC_ALL=$CC_LOCALE

# ── assertions ────────────────────────────────────────────────────────────────

test_case() { CC_CURRENT=$1; rm -f $CC_TEST_DIR/answer $CC_TEST_DIR/fail $CC_TEST_DIR/claude-args $CC_TEST_DIR/claude-stdin }

_cc_fail() {
  (( CC_FAILS++ ))
  print -r -- "  ✗ $CC_CURRENT: $1" >&2
}
_cc_pass() { (( CC_PASSES++ )) }

assert_eq() {  # expected actual [message]
  if [[ $1 == "$2" ]]; then _cc_pass; else _cc_fail "${3:-values differ}
      expected: ${(q+)1}
      actual:   ${(q+)2}"; fi
}
assert_contains() {  # haystack needle [message]
  if [[ $1 == *"$2"* ]]; then _cc_pass; else _cc_fail "${3:-missing ${(q+)2}}
      in: ${(q+)1}"; fi
}
assert_not_contains() {  # haystack needle [message]
  if [[ $1 != *"$2"* ]]; then _cc_pass; else _cc_fail "${3:-unexpected ${(q+)2}}
      in: ${(q+)1}"; fi
}
assert_true() {  # message command...
  local msg=$1; shift
  if "$@"; then _cc_pass; else _cc_fail "$msg"; fi
}

finish() {
  zpty -d 2>/dev/null
  rm -rf $CC_TEST_DIR
  print -r -- "  ${CC_PASSES} passed, ${CC_FAILS} failed"
  (( CC_FAILS == 0 ))
}

# ── interactive shell in a pseudo-terminal (zsh/zpty) ─────────────────────────────

typeset -g CC_PTY_OUT=""

# Start `zsh -f -i` with the plugin loaded. Extra arguments are NAME=value environment settings.
pty_start() {
  zpty -d cc 2>/dev/null
  CC_PTY_OUT=""
  zpty cc env -i HOME=$CC_TEST_DIR PATH=$PATH LANG=$LANG LC_ALL=$LC_ALL TERM=xterm-256color COLUMNS=120 LINES=40 \
    CC_TEST_DIR=$CC_TEST_DIR XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME "$@" zsh -f -i
  # ⌃T is a probe: it writes the line (BUFFER), the bottom area (POSTDISPLAY) and region_highlight to a file,
  # see pty_state
  cat >| $CC_TEST_DIR/setup.zsh <<SETUP
bindkey -e
PS1='PROMPT> '
source ${(q)CC_PLUGIN}
_cc_probe() { print -r -- "\$BUFFER@@SEP@@\$POSTDISPLAY@@HL@@\${(j:|:)region_highlight}" >| \$CC_TEST_DIR/state }
zle -N _cc_probe
bindkey '^T' _cc_probe
SETUP
  pty_send "source $CC_TEST_DIR/setup.zsh; print READY-\$((6*7))"$'\r'
  pty_expect 'READY-42' || { _cc_fail "interactive shell did not start: ${(q+)CC_PTY_OUT}"; return 1 }
  pty_expect 'PROMPT> '
  CC_PTY_OUT=""
}

pty_send() { _pty_drain; zpty -w -n cc "$1" }

# Read whatever the shell has written so far into CC_PTY_OUT. Must happen while waiting for anything: a
# pseudo-terminal buffers little (about 1 KB on macOS), and once it is full zle blocks on its next write, so
# the shell would stop handling keys, the probe included.
_pty_drain() {
  local chunk
  while zpty -r -t cc chunk 2>/dev/null; do CC_PTY_OUT+=$chunk; done
}

# Read until the output collected since the last pty_reset, without escape sequences, contains $1, or $2
# seconds pass. $1 is literal text in which only * is a wildcard.
pty_expect() {
  local pat=${(b)1} chunk
  pat=${pat//\\\*/*}
  local -F deadline=$(( EPOCHREALTIME + ${2:-5} ))
  while (( EPOCHREALTIME < deadline )); do
    _pty_drain
    [[ $(pty_text) == *${~pat}* ]] && return 0
    sleep 0.05
  done
  return 1
}

pty_reset() { CC_PTY_OUT="" }

# Ask the probe for the current state. Sets STATE_BUFFER, STATE_BOTTOM and STATE_HL (region_highlight
# entries joined with |).
typeset -g STATE_BUFFER STATE_BOTTOM STATE_HL
pty_state() {
  rm -f $CC_TEST_DIR/state
  _pty_drain
  zpty -w -n cc $'\x14'
  local -F deadline=$(( EPOCHREALTIME + 5 ))
  while [[ ! -s $CC_TEST_DIR/state ]] && (( EPOCHREALTIME < deadline )); do _pty_drain; sleep 0.05; done
  local s=$(<$CC_TEST_DIR/state)
  STATE_BUFFER=${s%%@@SEP@@*} STATE_BOTTOM=${${s#*@@SEP@@}%%@@HL@@*} STATE_HL=${s##*@@HL@@}
}

# Wait until the bottom area contains $1 (a plain string), or 5 seconds pass
pty_wait_bottom() {
  local -F deadline=$(( EPOCHREALTIME + ${2:-5} ))
  while (( EPOCHREALTIME < deadline )); do
    pty_state
    [[ $STATE_BOTTOM == *"$1"* ]] && return 0
    sleep 0.1
  done
  return 1
}

# The output collected so far with escape sequences and carriage returns removed
pty_text() {
  setopt localoptions extendedglob
  local t=${CC_PTY_OUT//$'\r'/}
  t=${t//$'\e'\[[0-9;?]#[a-zA-Z]/}
  print -r -- "${t//$'\e'[=>]/}"
}
