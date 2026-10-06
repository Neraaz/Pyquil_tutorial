# pyQuil 4 notebook migration: changes needed

**Source:** the interactive tutorials from Rigetti's QCS documentation, <https://docs.rigetti.com/qcs/guides/interactive-tutorials>.

**Environment:** Bridges-2, Python 3.12 venv, pyQuil 4, recent NumPy and pandas. The original tutorial environment used **pyQuil 3.0.0**. QAOA and H2 VQE match that version (they use `qc.run_experiment()`), but Meyer–Penny, teleportation, readout noise and Bell-state tomography still contained pyQuil 2.x code (`QVMConnection`, `qc.experiment()`) that 3.0.0 had already removed, so those cells would have failed on 3.0.0 as well. Below is every change that was needed to run all of them on pyQuil 4, grouped by cause.

**Pin `pyquil<5`:** pyQuil v5 plans to replace `pyquil.experiment` / `run_experiment` and to remove `pyquil.latex`, which these tutorials rely on.

---

## 1. `QVMConnection` removed

**Error:** `ImportError` / `AttributeError: ... no attribute 'QVMConnection'`

```python
# Old
from pyquil.api import QVMConnection
qvm = QVMConnection()

# New
from pyquil import get_qc
qvm = get_qc("2q-qvm")          # "Nq-qvm" for N qubits
```

## 2. `qc.run()` old call style (addresses + trials)

**Error:** `TypeError: argument 'params': 'list' object cannot be converted to 'PyDict'` (the address list gets passed in as `memory_map`)

```python
# Old
results = qvm.run(prog, [0, 1], trials=N)

# New
prog.wrap_in_numshots_loop(N)
results = qvm.run(prog).get_register_map()["ro"]    # (N, n_bits) array
```

The old `[a, b, ...]` addresses correspond to columns of the `ro` register: `results[:, a]`.

## 3. `qc.run()` returns an object, not a bit array

**Errors:**
- `TypeError: unsupported operand type(s) for /: 'QAMExecutionResult' and 'int'`
- `TypeError: 'QAMExecutionResult' object is not subscriptable`
- `AxisError: axis 0 is out of bounds for array of dimension 0`
- `IndexError: too many indices` (an `np.array` of result objects is 1-D)

**Fix:** add `.get_register_map()["ro"]` wherever a run result goes into NumPy.

```python
bits = qc.run(p).get_register_map()["ro"]
results.append(qc.run(p).get_register_map()["ro"])   # then np.array(results)
```

`res.readout_data.get("ro")` also works but raises a `DeprecationWarning`. pyQuil's own `run_experiment` still triggers that warning; silence it with:

```python
import warnings
warnings.filterwarnings("ignore", message=".*readout_data.*", category=DeprecationWarning)
```

## 4. `qc.experiment()` renamed

**Error:** `AttributeError: 'QuantumComputer' object has no attribute 'experiment'`

```python
# Old
results = qc.experiment(expt)

# New
results = qc.run_experiment(expt)
```

## 5. `run_experiment` memory-map size bug (pyQuil 4)

**Error:** `QVMError: Declared region measurement_gamma has size 2 but parameters have size 1`

**Fix:** run once before `run_experiment` / `calibrate`:

```python
from pyquil.experiment import Experiment

_orig = Experiment.build_setting_memory_map

def _padded(self, setting):
    mm = _orig(self, setting)
    for name, decl in self.generate_experiment_program().declarations.items():
        if name.startswith(("measurement_", "preparation_")):
            vals = list(mm.get(name, []))
            mm[name] = vals + [0.0] * (decl.memory_size - len(vals))
    return mm

Experiment.build_setting_memory_map = _padded
```

## 6. `ExperimentSetting` `in_state` must be a `TensorProductState`

**Error:** `AttributeError: 'PauliTerm' object has no attribute 'states'`

```python
# Old
ExperimentSetting(in_state=sZ(0)*sZ(1), out_operator=sZ(0)*sZ(1))

# New
from pyquil.experiment import plusZ
ExperimentSetting(in_state=plusZ(0)*plusZ(1), out_operator=sZ(0)*sZ(1))
```

| Old `in_state` | New `in_state` |
|---|---|
| `sI()` | `TensorProductState()` or `zeros_state(qubits)` |
| `sZ(q)` | `plusZ(q)` |
| `sX(q)` | `plusX(q)` |
| `sY(q)` | `plusY(q)` |

`out_operator` stays a `PauliTerm`.

For experiments with many settings (H2 VQE), convert them in place:

```python
from pyquil.experiment import ExperimentSetting, TensorProductState, plusX, plusY, plusZ

PLUS_STATE = {"X": plusX, "Y": plusY, "Z": plusZ}

def pauli_to_tensor_state(pt):
    state = TensorProductState()
    for q, op in pt:
        state = state * PLUS_STATE[op](q)
    return state

for group in expt:
    for i, s in enumerate(group):
        if not isinstance(s.in_state, TensorProductState):
            group[i] = ExperimentSetting(
                in_state=pauli_to_tensor_state(s.in_state),
                out_operator=s.out_operator,
                additional_expectations=s.additional_expectations,
            )
```

## 7. `ExperimentResult` field name

```python
# Old
result[0].run_expectation

# New
result[0].expectation        # standard error: result[0].std_err
```

## 8. `if_then` labels must be resolved (Meyer–Penny, teleportation)

**Error:** `ValueError: Label has not yet been resolved`

**Fix:** call this before `wrap_in_numshots_loop` / `run`:

```python
prog.resolve_label_placeholders()     # or prog.resolve_placeholders()
```

Run these programs on the `Nq-qvm` without `qc.compile()`, since quilc may reject classical control flow.

## 9. Qubit placeholders: exception type changed

**Error:** `ValueError: Qubit has not yet been resolved` (expected in the demo cell)

```python
# Old
except RuntimeError as e:

# New
except ValueError as e:
```

To resolve the placeholders: `prog.resolve_qubit_placeholders()`.

## 10. Random seed

```python
# Old
cxn.random_seed = hash((jj, kk))

# New
cxn.qam.random_seed = jj * len(p00s) + kk
```

- The seed now lives on `qc.qam`, not on the `QuantumComputer`.
- It must be a non-negative integer, and `hash()` can be negative.

## 11. Shot limit of 65,535

**Error:** `OverflowError: out of range integral type conversion attempted`

**Fix:** use at most 65,535 shots per run. For more, average equal-size chunks:

```python
ap = sum(estimate_assignment_probs(q, 50000, cxn, header) for _ in range(2)) / 2
```

A negative random seed gives the same error (see §10).

## 12. pandas: `float()` of a one-row Series

**Error:** `TypeError: float() argument must be a string or a real number, not 'Series'`

```python
# Old
float(error_min)
float(df[df.index == df.H.idxmin()].H_err)

# New
float(error_min.iloc[0])          # or error_min.item()
df.loc[df.H.idxmin(), "H_err"]
```

## 13. Python 3.12: invalid escape in LaTeX strings (warning only)

**Warning:** `SyntaxWarning: invalid escape sequence '\D'`

```python
# Old
"$\Delta E_{min}$"

# New
r"$\Delta E_{min}$"
```

## 14. Circuit diagrams: `pyquil.latex.display()`

**Error:** `'pdflatex' ... File 'standalone.cls' not found` (the system TeX Live 2018 lacks the packages)

**Fix**, run once from a notebook:

```python
!wget -qO- "https://yihui.org/tinytex/install-bin-unix.sh" | sh
!~/.local/bin/tlmgr install standalone quantikz pgf xkeyval currfile filemod gincltex adjustbox collectbox
!~/.local/bin/tlmgr install xargs environ trimspaces xstring tikz-cd mathtools etoolbox
```

Every kernel session:

```python
import os
os.environ["PATH"] = os.path.expanduser("~/.local/bin") + ":" + os.environ["PATH"]
```

The `standalone Warning: Conversion failed ... shell escape` message is harmless.

---

## Note: sign convention (not an error)

Some notebooks compute Z from bits as `2*bit - 1`, which maps bit 0 to −1. The standard ⟨Z⟩, where |0⟩ = +1, is `1 - 2*bit`. Products such as `Z1*Z2` are unaffected.
