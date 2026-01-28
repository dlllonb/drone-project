# file to contain functions called elsewhere for the pipeline
import function
import warnings
import numpy as np
import matplotlib.pyplot as plt
import pandas as pd

def imports():
    '''Just make sure we can import the functions in this file'''
    print("Successfully imported functions.")
    return

def unit(v: np.ndarray) -> np.ndarray:
    '''Normalize to a unit vector'''
    v = np.asarray(v, dtype=float).reshape(3)
    n = np.linalg.norm(v)
    if n == 0:
        raise ValueError("Zero-length vector cannot be normalized.")
    return v / n