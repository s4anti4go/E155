import os, sys, types
from .sim_overlay import Overlay
from .sim_mmio import MMIO

# Auto-install when QICK_BACKEND=sim
if os.getenv("QICK_BACKEND","").lower() == "sim":
    pynq = types.ModuleType("pynq")
    pynq.Overlay = Overlay
    pynq.MMIO    = MMIO
    sys.modules["pynq"] = pynq
