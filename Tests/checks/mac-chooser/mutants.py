#!/usr/bin/env python3
"""Expose chooser mutations to the shared runner and CI's mutants.py discovery."""
from pathlib import Path
import runpy
import sys

check = Path(__file__).with_name('check.py')
sys.argv = [str(check), '--mutants']
runpy.run_path(str(check), run_name='__main__')
