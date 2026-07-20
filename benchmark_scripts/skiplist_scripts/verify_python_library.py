import matplotlib
import numpy as np
import pandas as pd
'''
Matplotlib version: 3.9.3
NumPy version: 2.1.3
Pandas version: 2.2.3
'''

if matplotlib.__version__ != '3.9.3':
    print("version mismatch for matplotlib")
else:
    print("Run command python -m pip install --user matplotlib==3.9.3")

if np.__version__ != '2.1.3':
    print("version mismatch for numpy")
else:
    print("Run command python -m pip install --user numpy==2.1.3")

if pd.__version__ != '2.2.3':
    print("version mismatch for numpy")
else:
    print("Run command python -m pip install --user pandas==2.2.3")

print("Matplotlib version:", matplotlib.__version__)
print("NumPy version:", np.__version__)
print("Pandas version:", pd.__version__)