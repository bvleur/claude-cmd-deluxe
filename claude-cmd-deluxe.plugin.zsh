# claude-cmd-deluxe — text → zsh command via the Claude CLI (`claude -p`, so it uses the CLI's own gateway config)
#
#   ⌃G         generate, or modify an existing command with "command # instruction"
#   ⌃G         again: cycle through the 3 alternatives (no new call)
#   ⌃; / ⌃X e  explain the command in the buffer (⌃; in Ghostty; empty buffer: the previous command)
#   ⌃X f       fix the previous command (optionally type a hint first, e.g. the error message)
#   ⌃⇧;        show the key overview (Ghostty; elsewhere run claude-cmd-help)
#   ⌃_         undo (standard zle undo)
#
# Load it after your other plugins so its key bindings win. Every setting below can be overridden by setting
# the variable before the plugin is loaded. Features and design decisions: README.md.

(( $+commands[claude] )) || return 0

: ${CLAUDE_CMD_MODEL:=haiku}
: ${CLAUDE_CMD_LANG:=English}
: ${CLAUDE_CMD_GLOW_STYLE:=dark}
: ${CLAUDE_CMD_PREFS:=${XDG_CONFIG_HOME:-$HOME/.config}/claude-cmd/prefs.md}
: ${CLAUDE_CMD_CACHE:=${XDG_CACHE_HOME:-$HOME/.cache}/claude-cmd}
: ${CLAUDE_CMD_KEY_GEN:='^G'}
# Ghostty sends ⌃; as the kitty-keyboard sequence ESC [ 59 ; 5 u (Terminal.app sends nothing for it),
# so the explain key is ⌃; there and ⌃X e everywhere else.
if [[ $TERM_PROGRAM == ghostty ]]; then
  : ${CLAUDE_CMD_KEY_EXPLAIN:=$'\e[59;5u'}
else
  : ${CLAUDE_CMD_KEY_EXPLAIN:='^Xe'}
fi
: ${CLAUDE_CMD_KEY_FIX:='^Xf'}
if [[ $TERM_PROGRAM == ghostty ]]; then
  : ${CLAUDE_CMD_KEY_HELP:=$'\e[59;6u'}
else
  : ${CLAUDE_CMD_KEY_HELP:=}   # empty: no key, use the claude-cmd-help command
fi
# Binaries checked individually, next to `brew leaves` (which gives package names, not binaries)
(( ${+CLAUDE_CMD_CANDIDATES} )) || typeset -ga CLAUDE_CMD_CANDIDATES=(
  rg fd bat eza zoxide fzf jq yq xh httpie sd delta dust duf procs btop hyperfine
  tldr gh glab git zed code docker podman kubectl k9s helm terraform aws gcloud az
  gsed gdate gfind gxargs gls gtar mise uv node npm pnpm bun python3 go java mvn gradle
)

zmodload zsh/parameter 2>/dev/null

typeset -ga _cc_alts _cc_labels
typeset -gi _cc_idx=0 _cc_last_status=0
typeset -g  _cc_os="$OSTYPE"
(( $+commands[sw_vers] )) && _cc_os="macOS $(sw_vers -productVersion 2>/dev/null) (BSD userland)"

# ── context ──────────────────────────────────────────────────────────────────

_cc_refresh_tools() {
  local f=$CLAUDE_CMD_CACHE/brew-leaves.txt
  mkdir -p $CLAUDE_CMD_CACHE
  if (( $+commands[brew] )); then
    brew leaves 2>/dev/null | tr '\n' ' ' >| $f.tmp && mv -f $f.tmp $f
  else
    : >| $f
  fi
}

_cc_tools_stale() {
  local -a fresh=( $CLAUDE_CMD_CACHE/brew-leaves.txt(Nmh-24) )
  (( ! ${#fresh} ))
}

_cc_context() {
  emulate -L zsh
  local leaves="" prefs="(none)" gitinfo="" c
  local -a found
  [[ -r $CLAUDE_CMD_CACHE/brew-leaves.txt ]] && leaves=$(<$CLAUDE_CMD_CACHE/brew-leaves.txt)
  for c in $CLAUDE_CMD_CANDIDATES; do (( $+commands[$c] )) && found+=$c; done
  [[ -r $CLAUDE_CMD_PREFS ]] && prefs=$(<$CLAUDE_CMD_PREFS)
  if command git rev-parse --is-inside-work-tree &>/dev/null; then
    gitinfo=" (git repo, branch: $(command git branch --show-current 2>/dev/null))"
  fi
  print -r -- "OS: $_cc_os
Shell: zsh
Current directory: $PWD$gitinfo
Installed binaries (verified on PATH): ${found[*]}
Installed Homebrew packages (package names, not always binary names): ${leaves:-unknown}

User preferences:
$prefs"
}

# ── prompts ──────────────────────────────────────────────────────────────────

_cc_sys_commands() {
  print -r -- "You generate zsh commands for the user's machine, described in <context>.

Output EXACTLY 3 alternatives and nothing else, in this format:
@@@ <short label, max 4 words, in $CLAUDE_CMD_LANG>
<command>
@@@ <short label>
<command>
@@@ <short label>
<command>

Rules:
- The command lines contain only the command: no markdown, no code fences, no explanation, no comments.
- The first alternative is your best answer. The others must differ meaningfully: another tool, another approach, or a safer variant (dry run, interactive, narrower scope). No trivial variations.
- Use only binaries from the installed list or standard OS built-ins.
- Follow the user preferences strictly.
- Never invent options. When unsure an option exists in this OS's version of a tool, choose a different approach.
- Use sudo only when strictly necessary.
- Prefer a single line; use multiple lines only when unavoidable."
}

_cc_sys_explain() {
  print -r -- "Explain the given zsh command, in $CLAUDE_CMD_LANG, for the machine described in <context>.
Output GitHub-flavoured markdown, which is rendered in the terminal. Translate every label below into $CLAUDE_CMD_LANG.

Start with one sentence on what the command does as a whole.

A simple command (no &&, ||, ; or |): one markdown table with the columns Part and Meaning, one row per option or
argument, in command order.

A compound command: split it into steps at every &&, ||, ; and |. For every step, in command order:
1. A line with the step number and the step itself, like: **1.** \`git branch --merged main\`
2. A table with the columns Part and Meaning for that step only: the command and each of its options and arguments
   in its own row. Operators never get a row.
3. Unless it is the last step, one line that connects it to the next step, saying what the operator does, followed
   by what the step produces:
   - after |: what flows into the next step, as 'I expect output like:' plus a short realistic example, either a
     few values in backticks on the same line or a \`\`\`text block of at most 4 lines;
   - after &&: 'only if this succeeds', after ||: 'only if this fails', after ;: 'then, regardless of the result'.

Rules:
- Wrap every command, option, path and example value in backticks, and write a literal pipe character in a table
  cell as \\| so it does not split the cell.
- Code fences always get a language: \`\`\`sh for commands, \`\`\`text for output.
- If the command is destructive or irreversible, end with a line starting with '⚠ ' that says what can be lost.
- If an option does not exist on this OS's version of the tool, say so in its row.
- No headings, no nested lists, no arrows, no preamble, no closing remarks. Keep every Meaning cell to one short
  sentence."
}

# ── claude ───────────────────────────────────────────────────────────────────

# $1 = system prompt, $2 = user message → stdout; stderr in $CLAUDE_CMD_CACHE/last-error
_cc_call() {
  mkdir -p $CLAUDE_CMD_CACHE
  print -r -- "$2" | command claude -p \
    --model "$CLAUDE_CMD_MODEL" \
    --system-prompt "$1" \
    --tools "" \
    --strict-mcp-config \
    --disable-slash-commands \
    --no-session-persistence \
    2>| $CLAUDE_CMD_CACHE/last-error
}

_cc_error_msg() {
  local -a errlines
  [[ -r $CLAUDE_CMD_CACHE/last-error ]] && errlines=( ${(f)"$(<$CLAUDE_CMD_CACHE/last-error)"} )
  local err=${errlines[1]}
  print -rn -- "claude: no usable answer${err:+ — $err}"
}

# Parse "@@@ label\ncommand…" blocks into _cc_alts / _cc_labels
_cc_parse() {
  emulate -L zsh
  setopt extendedglob
  _cc_alts=() _cc_labels=()
  local line cur="" label="" started=0 nl=$'\n'
  local -a lines=( "${(@f)1}" )

  _cc_flush() {
    while [[ $cur == [[:space:]]* ]]; do cur=${cur[2,-1]}; done
    while [[ $cur == *[[:space:]] ]]; do cur=${cur[1,-2]}; done
    if [[ -n $cur ]]; then _cc_alts+=("$cur"); _cc_labels+=("$label"); fi
    cur=""
  }

  for line in "${lines[@]}"; do
    if [[ $line == '@@@'* ]]; then
      (( started )) && _cc_flush
      label=${${line#@@@}##[[:space:]]#}; started=1
    elif [[ $line == '```'* ]]; then
      continue
    elif (( started )); then
      cur+="${cur:+$nl}$line"
    fi
  done
  if (( started )); then
    _cc_flush
  else
    # the model ignored the format: treat the whole output as one alternative
    cur=${(F)${lines:#'```'*}}; label=""; _cc_flush
  fi
  unfunction _cc_flush
}

# Markdown on stdin → coloured text on stdout, via glow (same invocation as the yazi previewer and `v`).
# Fences without a language are treated as `sh`, so shell snippets always get syntax highlighting.
# Falls back to the raw markdown when glow is missing.
_cc_render() {
  local md
  md=$(command awk '
    /^[[:space:]]*```[[:space:]]*$/ { if (!open) { sub(/```.*/, "```sh") } open = !open; print; next }
    /^[[:space:]]*```/              { open = 1 }
    { print }
  ')
  if (( $+commands[glow] )); then
    print -r -- "$md" | CLICOLOR_FORCE=1 command glow -w=${COLUMNS:-80} -s=$CLAUDE_CMD_GLOW_STYLE -
  else
    print -r -- "$md"
  fi
}

# ── info bar ──────────────────────────────────────────────────────────────────

_cc_keylabel() {
  local k=$1 r
  if [[ $k == $'\e[59;5u' ]]; then
    print -rn -- '⌃;'
  elif [[ $k == $'\e[59;6u' ]]; then
    print -rn -- '⌃⇧;'
  elif [[ $k == '^['?* ]]; then
    print -rn -- "⌥${(U)k[3,-1]}"
  elif [[ $k == '^'?* ]]; then
    r=${k[3,-1]}; print -rn -- "⌃${(U)k[2]}${r:+ $r}"
  else
    print -rn -- $k
  fi
}

_cc_hints() {  # $1 = label for the generate key
  print -rn -- "$(_cc_keylabel $CLAUDE_CMD_KEY_GEN) ${1:-generate}   $(_cc_keylabel $CLAUDE_CMD_KEY_EXPLAIN) explain   $(_cc_keylabel $CLAUDE_CMD_KEY_FIX) fix previous   ⌃_ undo"
}

_cc_is_destructive() {
  emulate -L zsh
  local -a res=(
    # the tool in command position: at the start, after ; & | ( or after a wrapper such as sudo or xargs
    '(^|[;&|(])[[:space:]]*((sudo|xargs|exec|command|nohup|time|env)([[:space:]]+-[^[:space:]]+)*[[:space:]]+)*(rm|rmdir|dd|shred|truncate|diskutil|kill|killall|pkill|mkfs[.a-z0-9]*)([[:space:]]|$)'
    '(^|[[:space:]])(-rf|-fr|--force|--delete|--hard|--no-preserve-root|-delete)([[:space:]]|$)'
    '-exec[[:space:]]+rm'
    'git[[:space:]]+(clean|reset[^;|]*--hard|push[^;|]*(--force|-f)|checkout[[:space:]]+--[[:space:]]|restore)'
    '(chmod|chown)[[:space:]]+-R'
    '(DROP|TRUNCATE)[[:space:]]+(TABLE|DATABASE)'
  )
  local re
  for re in $res; do
    [[ $1 =~ $re ]] && return 0
  done
  return 1
}

# ── bottom area ──────────────────────────────────────────────────────────────
#
# Everything claude-cmd shows goes in POSTDISPLAY: zle draws it under the line, you can keep typing, and it is
# cleared when the line is accepted (_cc_line_finish). zle prints escape codes in POSTDISPLAY literally, so
# coloured text (glow's output) is split into plain text plus colour spans (_cc_ansi_parse). The spans become
# region_highlight entries, which zle positions from the start of BUFFER, so they are rebuilt before every
# redraw (_cc_pre_redraw): when you type, the bottom area moves and its colours move with it.

typeset -ga _cc_spans _cc_hl_added   # spans: "start end spec" within POSTDISPLAY · entries we put in region_highlight

# Split text with ANSI SGR colour codes. Sets REPLY to the plain text and reply to "start end spec" spans, with
# spec in region_highlight syntax (fg=203,bold). Other escape sequences are dropped.
_cc_ansi_parse() {
  emulate -L zsh
  setopt extendedglob
  local rest=$1 plain="" chunk p fg="" bg="" bold=0 ul=0 spec start=0
  local -a ps
  reply=()

  _cc_span_end() {   # close the span that runs from $start to the end of $plain
    local -a sp=()
    [[ -n $fg ]] && sp+=(fg=$fg)
    [[ -n $bg ]] && sp+=(bg=$bg)
    (( bold )) && sp+=(bold)
    (( ul )) && sp+=(underline)
    spec=${(j:,:)sp}
    (( ${#plain} > start )) && [[ -n $spec ]] && reply+=("$start ${#plain} $spec")
    start=${#plain}
  }

  while [[ $rest == *$'\e'* ]]; do
    plain+=${rest%%$'\e'*}
    rest=${rest#*$'\e'}
    if [[ $rest == (#b)\[([0-9\;]#)([@-~])* ]]; then
      rest=${rest:$(( ${#match[1]} + 2 ))}
      [[ $match[2] == m ]] || continue
      _cc_span_end
      ps=( ${(s:;:)match[1]} ); (( ${#ps} )) || ps=(0)
      while (( ${#ps} )); do
        p=${ps[1]}; shift ps
        case $p in
          (|0)       fg="" bg="" bold=0 ul=0 ;;
          (1)        bold=1 ;;
          (22)       bold=0 ;;
          (4)        ul=1 ;;
          (24)       ul=0 ;;
          (3[0-7])   fg=$(( p - 30 )) ;;
          (9[0-7])   fg=$(( p - 90 + 8 )) ;;
          (39)       fg="" ;;
          (4[0-7])   bg=$(( p - 40 )) ;;
          (10[0-7])  bg=$(( p - 100 + 8 )) ;;
          (49)       bg="" ;;
          (38|48)
            if [[ ${ps[1]} == 5 ]]; then
              chunk=${ps[2]}; shift 2 ps
            elif [[ ${ps[1]} == 2 ]]; then
              chunk=$(printf '#%02x%02x%02x' ${ps[2]:-0} ${ps[3]:-0} ${ps[4]:-0}); shift 4 ps
            else
              chunk=""
            fi
            [[ $p == 38 ]] && fg=$chunk || bg=$chunk ;;
        esac
      done
    elif [[ $rest == \]* ]]; then     # OSC (e.g. a hyperlink): drop up to BEL or ESC \
      rest=${rest#*($'\a'|$'\e'\\)}
    else
      rest=${rest:1}
    fi
  done
  plain+=$rest
  _cc_span_end
  unfunction _cc_span_end
  REPLY=$plain
}

# Show $1 (plain text, may contain ANSI colour) in the bottom area. Empty $1 clears it.
_cc_bar() {
  local -a reply
  local REPLY s
  _cc_ansi_parse "$1"
  _cc_spans=()
  if [[ -n $REPLY ]]; then
    POSTDISPLAY=$'\n'$REPLY
    for s in $reply; do      # +1 for the newline in front
      s=(${=s}); _cc_spans+=("$(( s[1] + 1 )) $(( s[2] + 1 )) ${s[3]}")
    done
  else
    POSTDISPLAY=""
  fi
  _cc_pre_redraw
  zle -R
}

# Before every redraw: put the colour spans at their current position (they start after BUFFER)
_cc_pre_redraw() {
  local s
  local -a parts
  (( ${#_cc_hl_added} )) && region_highlight=( ${region_highlight:|_cc_hl_added} )
  _cc_hl_added=()
  if [[ -n $POSTDISPLAY ]]; then
    for s in $_cc_spans; do
      parts=(${=s})
      _cc_hl_added+=("$(( ${#BUFFER} + parts[1] )) $(( ${#BUFFER} + parts[2] )) ${parts[3]}")
    done
    region_highlight+=( $_cc_hl_added )
  fi
}

_cc_line_finish() {
  POSTDISPLAY=""
  _cc_spans=()
  _cc_pre_redraw
}

autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-finish _cc_line_finish
add-zle-hook-widget line-pre-redraw _cc_pre_redraw

_cc_show() {
  BUFFER=${_cc_alts[_cc_idx]}
  CURSOR=$#BUFFER
  local warn="" label=${_cc_labels[_cc_idx]}
  _cc_is_destructive "$BUFFER" && warn="⚠ destructive — read carefully before you press Enter
"
  _cc_bar "${warn}✦ claude ${_cc_idx}/${#_cc_alts}${label:+ · $label}   │   $(_cc_hints next)"
}

_cc_busy() {
  _cc_bar "⏳ claude ($CLAUDE_CMD_MODEL) $1…"
}

# ── widgets ──────────────────────────────────────────────────────────────────

_cc_request() {  # $1 = user message
  local out
  out=$(_cc_call "$(_cc_sys_commands)" "<context>
$(_cc_context)
</context>

$1")
  _cc_parse "$out"
  if (( ! ${#_cc_alts} )); then
    _cc_bar "$(_cc_error_msg)"
    return 1
  fi
  _cc_idx=1
  _cc_show
}

#: zle widget (⌃G): turn the typed description into a command, repeat to cycle alternatives
claude-cmd-generate() {
  # Cycle: the buffer is still exactly the current alternative
  if (( ${#_cc_alts} > 1 && _cc_idx )) && [[ $BUFFER == ${_cc_alts[_cc_idx]} ]]; then
    _cc_idx=$(( _cc_idx % ${#_cc_alts} + 1 ))
    _cc_show
    return
  fi
  if [[ -z ${BUFFER//[[:space:]]/} ]]; then
    _cc_bar "claude: first type what you want to do   │   $(_cc_hints)"
    return
  fi
  _cc_busy "thinking"
  _cc_request "Input (natural-language request, an existing command to fix/improve, or a command followed by '# <instruction>' to modify it accordingly):
$BUFFER"
}

#: zle widget (⌃; in Ghostty, ⌃X e elsewhere): explain the command on the line, or the previous one
claude-cmd-explain() {
  local target=$BUFFER
  [[ -z ${target//[[:space:]]/} ]] && target=${history[$(( HISTCMD - 1 ))]}
  if [[ -z $target ]]; then
    _cc_bar "claude: nothing to explain"
    return
  fi
  _cc_busy "explaining"
  local out
  out=$(_cc_call "$(_cc_sys_explain)" "<context>
$(_cc_context)
</context>

Command:
$target")
  if [[ -z ${out//[[:space:]]/} ]]; then
    _cc_bar "$(_cc_error_msg)"
  else
    _cc_bar "$(print -r -- "$out" | _cc_render)"
  fi
}

#: zle widget (⌃X f): fix the previous failed command
claude-cmd-fix() {
  local last=${history[$(( HISTCMD - 1 ))]}
  if [[ -z $last ]]; then
    _cc_bar "claude: no previous command found"
    return
  fi
  local hint=${BUFFER//[[:space:]]/}
  hint=${hint:+$BUFFER}
  _cc_busy "fixing"
  _cc_request "Fix the previous command so it does what the user intended.
Previous command (exit status $_cc_last_status):
$last
User hint about what went wrong: ${hint:-none}"
}

_cc_precmd() { _cc_last_status=$? }
precmd_functions=(_cc_precmd ${precmd_functions:#_cc_precmd})

zle -N claude-cmd-generate
zle -N claude-cmd-explain
zle -N claude-cmd-fix
bindkey "$CLAUDE_CMD_KEY_GEN" claude-cmd-generate
bindkey "$CLAUDE_CMD_KEY_EXPLAIN" claude-cmd-explain
bindkey "$CLAUDE_CMD_KEY_FIX" claude-cmd-fix
[[ -n $CLAUDE_CMD_KEY_HELP ]] && { zle -N claude-cmd-help-widget; bindkey "$CLAUDE_CMD_KEY_HELP" claude-cmd-help-widget; }

# ── helper commands ────────────────────────────────────────────────────────────

#: edit the claude-cmd preferences (preferred CLI tools, option style) via chezmoi
claude-cmd-prefs() {
  if (( $+commands[chezmoi] )) && chezmoi source-path "$CLAUDE_CMD_PREFS" &>/dev/null; then
    chezmoi edit --apply "$CLAUDE_CMD_PREFS"
  else
    ${=EDITOR:-vi} "$CLAUDE_CMD_PREFS"
  fi
}

#: refresh the list of installed tools that claude-cmd sends as context
claude-cmd-refresh() {
  _cc_refresh_tools && print -r -- "claude-cmd: tool list refreshed ($(wc -w <$CLAUDE_CMD_CACHE/brew-leaves.txt | tr -d ' ') Homebrew packages)"
}

#: show exactly what context claude-cmd sends to Claude
claude-cmd-context() { _cc_context }

#: overview of the widget's keys, rendered as markdown; calls no model
claude-cmd-help() {
  emulate -L zsh
  local help helprow=""
  [[ -n $CLAUDE_CMD_KEY_HELP ]] && helprow="| \`$(_cc_keylabel $CLAUDE_CMD_KEY_HELP)\` | This overview. |"$'\n'
  help="# claude-cmd

| Key | What |
|---|---|
| \`$(_cc_keylabel $CLAUDE_CMD_KEY_GEN)\` | Turn the text in the buffer into a command. Modify an existing command with \`command # instruction\`. |
| \`$(_cc_keylabel $CLAUDE_CMD_KEY_GEN)\` again | Next of the three alternatives (local, no new request). |
| \`$(_cc_keylabel $CLAUDE_CMD_KEY_EXPLAIN)\` | Explain the command in the buffer (empty: the previous command). |
| \`$(_cc_keylabel $CLAUDE_CMD_KEY_FIX)\` | Fix the previous command. Type a hint first, e.g. the error message. |
| \`⌃_\` | Undo. |
${helprow}
Helpers: \`claude-cmd-prefs\`, \`claude-cmd-refresh\`, \`claude-cmd-context\`."
  print -r -- "$help" | _cc_render
}

#: zle widget (⌃⇧; in Ghostty): shows the overview above the prompt, without a model call
claude-cmd-help-widget() {
  _cc_bar "$(claude-cmd-help)"
}

# Opt-in for a `help` command that lists the `#:` description lines of the files in $HELP_SOURCES: when that
# array exists, add this file to it
(( ${+HELP_SOURCES} )) && HELP_SOURCES+=( ${${(%):-%x}:A} )

# Refresh the tool list at most once per 24 hours, in the background
_cc_tools_stale && { _cc_refresh_tools &! } 2>/dev/null
