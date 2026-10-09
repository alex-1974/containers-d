#!/usr/bin/env bash
set -euo pipefail

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
    pwd
)"
cd "$root"

compiler="${DC:-dmd}"
out_dir="${1:-build/research/m8-nested-minimal}"
mkdir -p "$out_dir/bin" "$out_dir/logs"

compiler_name="$(basename "$compiler")"
case "$compiler_name" in
    ldc2|ldmd2)
        version_prefix="--d-version="
        ;;
    *)
        version_prefix="-version="
        ;;
esac

modes=(
    TraitsProbe
    OrdinaryMoveProbe
    PlacementConstructProbe
    PlacementDestroyProbe
)

results="$out_dir/results.txt"
: > "$results"

printf 'compiler=%s\n' "$compiler" | tee -a "$results"
"$compiler" --version 2>&1 | head -n 3 | sed 's/^/compiler-version: /' | tee -a "$results"
printf '\n' | tee -a "$results"

for mode in "${modes[@]}"; do
    exe="$out_dir/bin/$mode"
    compile_log="$out_dir/logs/$mode.compile.txt"
    run_log="$out_dir/logs/$mode.run.txt"

    printf '=== %s ===\n' "$mode" | tee -a "$results"

    set +e
    "$compiler"         -g         "${version_prefix}${mode}"         "-of=$exe"         experiments/m8_nested_elements/minimal/probe.d         >"$compile_log" 2>&1
    compile_status=$?
    set -e

    if ((compile_status != 0)); then
        printf 'compile=FAIL status=%d\n' "$compile_status" | tee -a "$results"
        sed 's/^/compile-log: /' "$compile_log" | tee -a "$results"
        printf '\n' | tee -a "$results"
        continue
    fi

    printf 'compile=PASS\n' | tee -a "$results"

    set +e
    "$exe" >"$run_log" 2>&1
    run_status=$?
    set -e

    if ((run_status == 0)); then
        printf 'run=PASS\n' | tee -a "$results"
    else
        printf 'run=FAIL status=%d\n' "$run_status" | tee -a "$results"
    fi

    sed 's/^/run-log: /' "$run_log" | tee -a "$results"
    printf '\n' | tee -a "$results"
done

echo "PASS: minimal reproducer matrix recorded"
