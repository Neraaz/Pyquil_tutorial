#!/bin/bash
# Start qvm and quilc in the background, run a pyQuil script, then stop the servers.
# Usage: ./run_bell.sh [script.py]    (defaults to test_bell.py)
# Run on the compute node where the job runs; servers and script must share a node.

VENV=/ocean/projects/pscstaff/nnepal/Rigetti/.venv
SCRIPT=${1:-test_bell.py}

source "$VENV/bin/activate"

# Stop both servers when this script exits, even after an error or Ctrl+C.
cleanup() {
    kill "$QVM_PID" "$QUILC_PID" 2>/dev/null
    wait "$QVM_PID" "$QUILC_PID" 2>/dev/null
}
trap cleanup EXIT

qvm -S > qvm.log 2>&1 &
QVM_PID=$!
quilc -P -S > quilc.log 2>&1 &
QUILC_PID=$!

# Wait up to 30 s for each server's port to open, instead of a fixed sleep.
wait_for_port() {
    local name=$1 port=$2 pid=$3
    for _ in $(seq 1 30); do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "ERROR: $name exited on startup. Last lines of $name.log:" >&2
            tail -n 20 "$name.log" >&2
            exit 1
        fi
        (echo > /dev/tcp/127.0.0.1/"$port") 2>/dev/null && return 0
        sleep 1
    done
    echo "ERROR: $name did not open port $port within 30 s. See $name.log." >&2
    exit 1
}

wait_for_port qvm 5000 "$QVM_PID"
wait_for_port quilc 5555 "$QUILC_PID"
echo "qvm (port 5000) and quilc (port 5555) are running."

python "$SCRIPT"
