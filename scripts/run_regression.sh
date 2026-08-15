#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 MODULE [NUM_SEEDS]"
    exit 1
fi

MODULE="$1"
NUM_SEEDS=${2:-1}

RTL="rtl/${MODULE}.sv"
TB="tb/${MODULE}_tb.sv"
TB_TOP="${MODULE}_tb"
SIM="obj_dir/V${MODULE}_tb"
NETLIST="synth_${MODULE}.v"

TOTAL_IN=0
TOTAL_OUT=0
TOTAL_STALLS=0
TOTAL_SIMULTANEOUS=0

if [ ! -f "$RTL" ]; then
    echo "Missing RTL: $RTL"
    exit 1
fi

if [ ! -f "$TB" ]; then
    echo "Missing testbench: $TB"
    exit 1
fi

mkdir -p results

echo "[1/4] Linting $MODULE"

if ! verilator --lint-only "$RTL" > results/lint.log 2>&1; then
    cat results/lint.log
    exit 1
fi

echo "[2/4] Building simulation"

if ! verilator --binary --timing --assert --trace \
    "$RTL" \
    "$TB" \
    --top-module "$TB_TOP" > results/build.log 2>&1; then

    cat results/build.log
    exit 1
fi

echo "[3/4] Running $NUM_SEEDS simulation seeds"

for ((seed=1; seed<=NUM_SEEDS; seed++)); do
    LOG="results/sim_seed_${seed}.log"

    echo "  seed $seed"

    if ! "./$SIM" +verilator+seed+"$seed" > "$LOG" 2>&1; then
        cat "$LOG"
        echo "FAIL: $MODULE seed=$seed"
        exit 1
    fi

    COVERAGE=$(grep "Coverage:" "$LOG")

    IN=$(echo "$COVERAGE" |
        sed -E 's/.*in=([0-9]+).*/\1/')

    OUT=$(echo "$COVERAGE" |
        sed -E 's/.*out=([0-9]+).*/\1/')

    STALLS=$(echo "$COVERAGE" |
        sed -E 's/.*stalls=([0-9]+).*/\1/')

    SIMULTANEOUS=$(echo "$COVERAGE" |
        sed -E 's/.*simultaneous=([0-9]+).*/\1/')

    TOTAL_IN=$((TOTAL_IN + IN))
    TOTAL_OUT=$((TOTAL_OUT + OUT))
    TOTAL_STALLS=$((TOTAL_STALLS + STALLS))
    TOTAL_SIMULTANEOUS=$((TOTAL_SIMULTANEOUS + SIMULTANEOUS))
done

echo
echo "Regression coverage:"
echo "  input transfers:        $TOTAL_IN"
echo "  output transfers:       $TOTAL_OUT"
echo "  stall cycles:           $TOTAL_STALLS"
echo "  simultaneous transfers: $TOTAL_SIMULTANEOUS"

if [ "$TOTAL_IN" -eq 0 ]; then
    echo "FAIL: regression generated no input traffic"
    exit 1
fi

if [ "$TOTAL_IN" -ne "$TOTAL_OUT" ]; then
    echo "FAIL: input/output transfer totals do not match"
    exit 1
fi

if [ "$TOTAL_STALLS" -eq 0 ]; then
    echo "FAIL: regression never exercised backpressure"
    exit 1
fi

if [ "$TOTAL_SIMULTANEOUS" -eq 0 ]; then
    echo "FAIL: regression never exercised simultaneous transfers"
    exit 1
fi

echo "[4/4] Synthesizing $MODULE"

if ! yosys \
    -p "read_verilog -sv $RTL; synth -top $MODULE; write_verilog $NETLIST" \
    > results/synthesis.log 2>&1; then

    cat results/synthesis.log
    exit 1
fi

echo
echo "REGRESSION PASS: $MODULE ($NUM_SEEDS seeds)"