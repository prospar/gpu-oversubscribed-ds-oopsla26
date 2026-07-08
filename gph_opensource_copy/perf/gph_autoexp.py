import sys 
sys.path.append('./autoexp/')

from autoexp import autoexp
autoexp("perf/gph_autoexp_autotune.json", False)
