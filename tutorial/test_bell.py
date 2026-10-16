import warnings
from collections import Counter

from pyquil._deprecation import PyQuilDeprecationWarning
# Hide pyQuil 4.22's notices that the QVM is deprecated in favour of pyQuil v5
# (the QVM still works; see 0_Jupyter_Pykernel_from_Container_image.ipynb).
warnings.filterwarnings("ignore", category=PyQuilDeprecationWarning)

from pyquil import get_qc, Program
from pyquil.gates import CNOT, Z, MEASURE, H
from pyquil.quilbase import Declare

prog = Program(
    Declare("ro", "BIT", 2),
    H(0),
    CNOT(0, 1),
    MEASURE(0, ("ro", 0)),
    MEASURE(1, ("ro", 1)),
).wrap_in_numshots_loop(1024)

# qvm and quilc are started by run_bell.sh, so no local_forest_runtime() here.
qvm = get_qc("9q-square-qvm")
bitstrings = qvm.run(qvm.compile(prog)).get_register_map().get("ro")

# Each row is one shot, e.g. [0 1]. Join the bits into a string like "01".
counts = Counter("".join(str(bit) for bit in shot) for shot in bitstrings)

print("State  Count")
for state, count in sorted(counts.items()):
    print(f"|{state}>  {count}")

print(dict(sorted(counts.items())))
