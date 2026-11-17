#!/usr/bin/env zsh
# Run all tests: `zsh tests/run.zsh` (or a subset: `zsh tests/run.zsh tests/unit.test.zsh`).
# Every test file runs in its own clean `zsh -f`, so one file can't influence another.
emulate -L zsh
local root=${0:A:h} f failed=0
local -a files=( ${@:-$root/*.test.zsh(N)} )
for f in $files; do
  print -r -- "${f:t}"
  zsh -f $f || failed=1
done
(( failed )) && print -r -- "FAILED" || print -r -- "OK"
return failed
