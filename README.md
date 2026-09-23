# Tutorial: pyQuil with quilc and QVM on Linux

Sep 23, 2026 · @Niraj

## Before you start

This tutorial sets up pyQuil in a Python virtual environment and runs Rigetti's `quilc` compiler and `QVM` simulator from the prebuilt Linux SDK tar file, with no Docker and no root access. You need:

- A Linux machine or cluster account with Python 3.10 or newer
- The **Linux barebones** SDK tar file from Rigetti's SDK downloads page (the `.deb` and `.rpm` versions need `sudo`)
  https://qcs.rigetti.com/sdk-downloads
- A working directory, for example `$WORK/Rigetti` on a TACC cluster

**Check your CPU first.** The prebuilt `quilc` and `qvm` programs are compiled for x86 only. Run:

```bash
uname -m
```

If it prints `x86_64`, follow every step below. If it prints `aarch64` (ARM, as on TACC Vista), the programs from the tar file will not run. Do Steps 1, 2 and 5, and use the ARM workaround in Troubleshooting instead of Steps 3 and 4.

## Step 1: Create a virtual environment

A virtual environment keeps pyQuil and its dependencies separate from the system Python and from your other projects.

```bash
cd $WORK/Rigetti
python -m venv .venv
source .venv/bin/activate
```

Your prompt now starts with `(.venv)`. Run the `source` line again in every new terminal or job script, and type `deactivate` to leave.

If conda is also active (your prompt shows `(base)`), run `conda deactivate` before creating the environment. That way `.venv` is built from a plain Python and the two don't mix.

## Step 2: Install pyQuil

With the environment active:

```bash
pip install --upgrade pip
pip install pyquil
```

Check the install:

```bash
python -c "import pyquil; print(pyquil.__version__)"
```

pyQuil is pure Python, so this step works on both x86 and ARM machines.

## Step 3: Install quilc and qvm from the tar file

Copy the barebones tar file to your working directory, then extract it and run its installer. It needs no root and installs into your home directory.

```bash
cd $WORK/Rigetti
tar -xf forest-sdk-linux-barebones.tar.bz2
cd forest-sdk-*-linux-barebones
./forest-sdk-*-linux-barebones.run

(you need to provide path, quilc and qvm executables will be generated, prefix_path)
```

Put the two programs where your environment can find them. The simplest way is to copy them into the virtual environment's `bin` folder, which is already on your PATH while `.venv` is active:

```bash
cp prefix_path/forest-sdk_2.23.0-linux-barebones/* /path_to_.venv/bin/
```

Confirm the architecture matches your machine before going on:

```bash
file .venv/bin/quilc
quilc --version
qvm --version
```

`file` should say `x86-64`, and both version commands should print a number.

## Step 3b: Give quilc the ZeroMQ library from inside .venv

`quilc` needs ZeroMQ, and without it `quilc -P -S` crashes with `Error opening shared object "libzmq.so"`. You can supply the library from pip, so everything stays inside `.venv`. pyzmq 25 ships a separate libzmq file, while versions 26 and later build it in and leave no file to use:

```bash
pip install "pyzmq<26" --force-reinstall
ls $VIRTUAL_ENV/lib64/python3.12/site-packages/pyzmq.libs/
```

You'll see two files, for example `libsodium-1c6bac97.so.26.4.0` and `libzmq-82f916e6.so.5.2.5` (the hash in the names may differ). `quilc` looks for the plain name `libzmq.so`, so copy the libzmq file to that name in the same folder:

```bash
cd $VIRTUAL_ENV/lib64/python3.12/site-packages/pyzmq.libs/
cp libzmq-82f916e6.so.5.2.5 libzmq.so
cd $WORK/Rigetti
```

Then make activating `.venv` add that folder to the library path. libzmq also needs the libsodium file next to it, so point to the whole folder:

```bash
echo 'export LD_LIBRARY_PATH="$VIRTUAL_ENV/lib64/python3.12/site-packages/pyzmq.libs:$LD_LIBRARY_PATH"' >> .venv/bin/activate
deactivate
source .venv/bin/activate
```

If your Python isn't 3.12, change `python3.12` in both paths to match. `qvm` also needs BLAS/LAPACK. On an HPC cluster, load them with `module load openblas` (find the name with `module spider openblas`).

## Step 4: Start the servers

pyQuil talks to `quilc` and `qvm` over the network at `127.0.0.1` ("this machine"), so both servers must run **on the same node as your Python script**. On a cluster, get a compute node first (for example `interact` on PSC Bridges-2, or `idev` on TACC) and do everything below on that one node.

```bash
source $WORK/Rigetti/.venv/bin/activate
qvm -S > qvm.log 2>&1 &
quilc -P -S > quilc.log 2>&1 &
sleep 5
```

| Server           | Command      | Default port |
| ---------------- | ------------ | ------------- |
| quilc (compiler) | `quilc -P -S` | 5555          |
| qvm (simulator)  | `qvm -S`      | 5000          |

`-S` starts server mode and `&` runs each server in the background, so you can keep using the same terminal. `> qvm.log 2>&1` saves each server's output to a log file. Check that both started:

```bash
tail qvm.log quilc.log
```

`qvm`'s log should end with `Starting server on port 5000`. Stop both servers when you're done with `kill %1 %2`.

## Step 5: Run a test program

Save this as `test_bell.py`. It builds a two-qubit Bell state and measures it 10 times:

```python
from pyquil import Program, get_qc
from pyquil.gates import H, CNOT

qc = get_qc("2q-qvm")  # use "2q-pyqvm" on ARM (see Troubleshooting)
p = Program(H(0), CNOT(0, 1))
p.measure_all()
p.wrap_in_numshots_loop(10)

result = qc.run(qc.compile(p))
print(result.get_register_map()["ro"])
```

Run it with the environment active:

```bash
python test_bell.py
```

Success looks like 10 rows that are each `[0 0]` or `[1 1]`, which is the correlated result a Bell state should give. A connection error means one of the servers from Step 4 isn't running.

**If your script uses `local_forest_runtime()`:** that helper starts its own `qvm` and `quilc`. With the servers from Step 4 already running, it prints `RuntimeWarning: Unable to start qvm server, since the specified port 5000 is in use` (and the same for quilc on 5555). These warnings are harmless, because the script just uses your running servers. To avoid them, either remove the `with local_forest_runtime():` line or skip Step 4 and let the script start the servers.

## Troubleshooting: "libzmq.so: cannot open shared object file"

If `quilc` stops with `Error opening shared object "libzmq.so"`, the ZeroMQ library isn't on the library path. Check three things:

- `ls $VIRTUAL_ENV/lib64/python3.12/site-packages/pyzmq.libs/libzmq.so` shows the file. If not, redo Step 3b.
- `echo $LD_LIBRARY_PATH` includes the `pyzmq.libs` folder. If not, reactivate `.venv` with `deactivate` then `source .venv/bin/activate`.
- `ldd $VIRTUAL_ENV/lib64/python3.12/site-packages/pyzmq.libs/libzmq.so | grep "not found"` prints nothing. Anything it prints is a missing dependency.

## Troubleshooting: "Could not communicate with QVM at http://127.0.0.1:5000"

pyQuil couldn't reach the `qvm` server. Check these in order:

1. **Is qvm running?** `ps -u $USER | grep qvm`. If not, start it as in Step 4.
2. **Did it crash on startup?** Run `qvm -S` in the foreground to see the message. A healthy start prints the "Welcome to the Rigetti QVM" banner and `Starting server on port 5000`. A missing `libblas` or `liblapack` means you need `module load openblas`, and a missing `libzmq.so` means Step 3b isn't active in this shell (reactivate `.venv`).
3. **Is it on the same node?** Servers started on the login node can't be reached from a compute node, and the reverse is also true. Check the node name in your prompt (for example `r092`) and run everything there.
4. **Is it answering?** `curl -s -X POST localhost:5000 -d '{"type":"version"}'` should print a version number.

## Troubleshooting: "Exec format error" on ARM (TACC Vista)

On TACC Vista, Step 4 fails like this:

```
$ quilc -P -S
-bash: .../.venv/bin/quilc: cannot execute binary file: Exec format error
$ qvm -S
-bash: .../.venv/bin/qvm: cannot execute binary file: Exec format error
```

Vista's NVIDIA Grace CPUs are ARM (aarch64), and the SDK's `quilc` and `qvm` are x86 programs. The `.deb`, `.rpm` and barebones downloads all contain the same x86 programs, so switching packages doesn't help. pyQuil itself is fine.

The workaround keeps Steps 1, 2 and 5 and replaces Steps 3 and 4:

1. Remove the x86 programs: `rm .venv/bin/quilc .venv/bin/qvm`
2. Run `quilc` from Rigetti's container, which has an ARM build:

   ```bash
   module load tacc-apptainer
   cd $WORK/Rigetti
   apptainer pull quilc.sif docker://rigetti/quilc:latest
   apptainer run quilc.sif -P -S &
   ```

3. Replace `qvm` with pyQuil's built-in Python simulator. No ARM build of `qvm` exists, but PyQVM needs no server. In `test_bell.py`, change `get_qc("2q-qvm")` to `get_qc("2q-pyqvm")`. If it complains about missing packages, run `pip install numpy scipy`.

PyQVM is slower than the real QVM and suits small circuits. For larger ones, either build `qvm` from source with SBCL (which supports ARM) or use the tar-file programs on an x86 system such as TACC Stampede3 or Frontera.
