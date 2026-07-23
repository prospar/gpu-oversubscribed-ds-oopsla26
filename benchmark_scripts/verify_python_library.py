from packaging.version import Version
import matplotlib
import numpy as np
import pandas as pd

requirements = {
    "matplotlib": ("3.9.3", matplotlib.__version__),
    "numpy": ("2.1.3", np.__version__),
    "pandas": ("2.2.3", pd.__version__),
}

for package, (required, installed) in requirements.items():
    if Version(installed) >= Version(required):
        print(f"{package}: OK ({installed})")
    else:
        print(f"{package}: version mismatch ({installed} < {required})")
        print(f"Run command: python -m pip install --user {package}=={required}")

print("\nInstalled versions:")
print("Matplotlib:", matplotlib.__version__)
print("NumPy:", np.__version__)
print("Pandas:", pd.__version__)