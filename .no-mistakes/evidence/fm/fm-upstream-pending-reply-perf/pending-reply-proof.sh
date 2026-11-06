#!/usr/bin/env bash
set -euo pipefail

base=8b1618a49511d67b247f5f8091868b812bfcae2d
head=aed78f3f956a3bdac3024804705c4c3a172dd22f
repo=$(pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-pending-reply-proof.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp"
git archive "$base" bin | tar -x -C "$tmp"
base_lib="$tmp/bin/fm-pending-reply-lib.sh"
target="$repo/bin/fm-pending-reply-lib.sh"
corr=1a2b3c4d5e6f7890

printf 'base=%s\nhead=%s\n' "$base" "$head"
printf 'oracle=whole-token corr=<id>; punctuation and whitespace delimit tokens; alphanumeric or underscore adjacency does not\n'

run_matrix() (
  local lib=$1 version=$2 actual label expected text
  . "$lib"
  check() {
    label=$1 expected=$2 text=$3
    if fm_pending_reply_line_resolves "$text" "$corr"; then actual=match; else actual=miss; fi
    if [ "$actual" != "$expected" ]; then
      printf 'FAIL %s %s expected=%s actual=%s text=%s\n' "$version" "$label" "$expected" "$actual" "$text"
      return 1
    fi
    printf 'PASS %s %s expected=%s actual=%s\n' "$version" "$label" "$expected" "$actual"
  }
  check exact match "corr=$corr"
  check punctuation match "ack: [corr=$corr], done"
  check whitespace match "ack corr=$corr done"
  check alphanumeric_prefix miss "xcorr=$corr"
  check underscore_prefix miss "_corr=$corr"
  check alphanumeric_suffix miss "corr=${corr}ff"
  check underscore_suffix miss "corr=${corr}_"
  check other_correlation miss 'corr=0000000000000000'
  check unrelated_line miss 'task=sample state=ready'
)

run_matrix "$base_lib" base
run_matrix "$target" target

status="$tmp/status.log"
for ((i=1; i<=4365; i++)); do
  printf '%-475s\n' "unrelated status row $i"
done > "$status"
bytes=$(wc -c < "$status" | tr -d ' ')
lines=$(wc -l < "$status" | tr -d ' ')
printf 'synthetic_status lines=%s bytes=%s\n' "$lines" "$bytes"
[ "$lines" = 4365 ] && [ "$bytes" = 2077740 ]
cat "$status" >/dev/null

python3 - "$base_lib" "$target" "$status" "$corr" <<'PY'
import subprocess
import sys
import time

for version, lib in (('base', sys.argv[1]), ('target', sys.argv[2])):
    command = 'source "$1"; result=$(fm_pending_reply_find_resolve_line "$2" "$3"); [[ -z $result ]]'
    started = time.perf_counter()
    result = subprocess.run(
        ['bash', '-c', command, 'scan', lib, sys.argv[3], sys.argv[4]],
        capture_output=True, text=True, check=True,
    )
    elapsed = time.perf_counter() - started
    if result.stdout or result.stderr:
        raise SystemExit(f'{version} unexpected output: {result.stdout!r} {result.stderr!r}')
    print(f'PASS {version} absent-correlation scan elapsed_seconds={elapsed:.3f} result=empty')
PY
