#!/usr/bin/env bash
set -euo pipefail

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.."
    pwd
)"
cd "$root"

compiler="${DC:-dmd}"
out_dir="${1:-build/research/m8-nested-elements}"
mkdir -p "$out_dir/bin" "$out_dir/logs"

probes=(
    module_scope
    local_no_capture
    local_capture
    member_capture
)

modes=(
    TraitsProbe
    OrdinaryMoveProbe
    PlacementMoveProbe
)

results="$out_dir/results.txt"
: > "$results"

printf 'compiler=%s\n' "$compiler" | tee -a "$results"
"$compiler" --version 2>&1 | sed 's/^/compiler-version: /' | tee -a "$results"
printf '\n' | tee -a "$results"

control_fail=0

for probe in "${probes[@]}"; do
    for mode in "${modes[@]}"; do
        src="experiments/m8_nested_elements/probes/$probe.d"
        exe="$out_dir/bin/$probe-$mode"
        compile_log="$out_dir/logs/$probe-$mode.compile.txt"
        run_log="$out_dir/logs/$probe-$mode.run.txt"

        printf '=== %s / %s ===\n' "$probe" "$mode" | tee -a "$results"

        compiler_name="$(basename "$compiler")"

        case "$compiler_name" in
            ldc2|ldmd2)
                version_flag="--d-version=$mode"
                ;;
            *)
                version_flag="-version=$mode"
                ;;
        esac

        set +e
        "$compiler" \
            -g \
            "$version_flag" \
            "-of=$exe" \
            "$src" \
            >"$compile_log" 2>&1
        status=$?
        set -e

        if ((status != 0)); then
            printf 'compile=FAIL status=%d\n' "$status" | tee -a "$results"
            sed 's/^/compile-log: /' "$compile_log" | tee -a "$results"

            if [[ "$probe" == "module_scope" ]]; then
                control_fail=1
            fi

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
done

if ((control_fail != 0)); then
    echo "error: module-scope control probe failed to compile" >&2
    exit 1
fi

echo "PASS: primitive matrix completed; nested/context failures are recorded as evidence"
