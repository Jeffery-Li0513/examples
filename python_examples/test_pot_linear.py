#!/usr/bin/env python3
def random_positions(n):
    """Returns n random 3-d vectors in a numpy array (n,3).
    d_min, d_max, npos should be in global scope"""

    import numpy as np
    from maths_module import random_vector
    import sys
    
    r = np.zeros((n,3),dtype='f8')
    # molecule 0 is always at the origin, now place the others randomly
    for i in range(1,r.shape[0]):
        for pos_try in range(npos):
            zeta   = np.random.rand()
            d      = d_min + (d_max-d_min)*zeta # Magnitude of r
            r[i,:] = random_vector()  * d       # In random direction
            ok = True
            for j in range(1,i): # Check intermediate molecules if any
                d = np.sqrt(np.sum((r[i,:]-r[j,:])**2))
                ok = ok and (d >= d_min ) and ( d <= d_max )
            if ok:
                break
        else:
            print('Exceeded maximum number of tries in random_positions')
            sys.exit()
    return r

def random_orientations(n):
    """Returns n random 3-d vectors in a numpy array (n,3)."""
    import numpy as np
    from maths_module import random_vector
    e = np.zeros((n,3),dtype='f8')
    for i in range(e.shape[0]):
        e[i,:] = random_vector()
    return e

# test_pot_linear program

import json
import sys
import importlib
import numpy as np
from maths_module import rotate_vector

print('test_pot_linear')

# Read parameters in JSON format
allowed_nml_keys = ["model","delta","d_min","d_max","pot_max","ntry","npos"]
allowed_models = ["dd","dq","qq","gb"]

try:
    nml = json.load(sys.stdin)
except json.JSONDecodeError:
    print('Exiting on Invalid JSON format')
    sys.exit()

if "model" not in nml:
    print('You must specify "model" as one of',allowed_models)
    sys.exit()

if nml["model"] not in allowed_models:
    print(nml["model"],'not in allowed_models',allowed_models)
    sys.exit()

pot_module = "test_pot_"+nml["model"]
try:
    model = importlib.import_module(pot_module)
except ImportError:
    print('Tried but failed to import',pot_module)
    print('Exiting on ImportError')
    sys.exit()

for key in nml:
    if key not in allowed_nml_keys:
        print('Warning', key, 'not in allowed_nml_keys',allowed_nml_keys)
    
# Set parameters to input values or defaults
delta   = nml["delta"]   if "delta"   in nml else 1.e-5 # Small displacement
d_min   = nml["d_min"]   if "d_min"   in nml else 0.3   # Minimum separation between molecules
d_max   = nml["d_max"]   if "d_max"   in nml else 1.5   # Maximum separation between molecules
pot_max = nml["pot_max"] if "pot_max" in nml else 10.0  # Maximum potential to allow in molecule placement
ntry    = nml["ntry"]    if "ntry"    in nml else 1000  # Number of attempts to make in order to place molecule
npos    = nml["npos"]    if "npos"    in nml else 1000  # Number of attempts to position each molecule

# Write out parameters
print ( "{:40}{:15.4e}".format('Displacement delta',          delta)   )
print ( "{:40}{:15.6f}".format('Min separation d_min',        d_min)   )
print ( "{:40}{:15.6f}".format('Max separation d_max',        d_max)   )
print ( "{:40}{:15.6f}".format('Max potential pot_max',       pot_max) )
print ( "{:40}{:15d}  ".format('Max placement tries',         ntry)    )
print ( "{:40}{:15d}  ".format('Max molecule position tries', npos)    )

np.random.seed()

# Make a number of attempts to place the molecules
for itry in range(ntry):
    e = random_orientations ( model.n )
    r = random_positions ( model.n )
    pot, f, t = model.force ( r, e ) # Calculation of potential and analytical forces & torques
    if pot < pot_max:
        break
else:
    print('Exceeded allowed number of tries')
    sys.exit()

print ( "{:40}{:15.6f}".format('Potential energy', pot ) )
tot = np.sum(f,axis=0)
print ( "{:40}{:15.4e}{:15.4e}{:15.4e}".format('Total force', *tot ) )
tot = np.sum(t+np.cross(r,f),axis=0)
print ( "{:40}{:15.4e}{:15.4e}{:15.4e}".format('Total torque', *tot ) )

print ( "{:>15}{:>15}{:>15}{:>15}".format('Atom Component','Exact','Numerical','Difference') )

cf = ['Fx','Fy','Fz']
ct = ['Tx','Ty','Tz']

for i_xyz, f_exact in np.ndenumerate(f):
    i   = i_xyz[0]
    xyz = i_xyz[1]
    rsave = r[i_xyz] # Save position
    r[i_xyz] = rsave + delta # Translate
    potp, fdum, tdum = model.force ( r, e )
    r[i_xyz] = rsave - delta # Translate
    potm, fdum, tdum = model.force ( r, e )
    r[i_xyz] = rsave # Restore position
    fnum = -(potp-potm)/(2.0*delta)
    print ( "{:5d}{:>10}{:15.6f}{:15.6f}{:15.4e}".format(i,cf[xyz],f_exact,fnum,f_exact-fnum) )

    t_exact = t[i_xyz] # Exact torque
    axis = np.zeros(3,dtype='f8')
    esave = np.zeros(3,dtype='f8')
    axis[xyz] = 1.0 # Pick axis
    esave[:] = e[i,:] # Save orientation vector (copy, not view)
    e[i,:] = rotate_vector ( delta, axis, esave ) # Rotate
    potp, fdum, tdum = model.force ( r, e )
    e[i,:] = rotate_vector ( -delta, axis, esave ) # Rotate
    potm, fdum, tdum = model.force ( r, e )
    e[i,:] = esave # Restore orientation vector
    tnum = -(potp-potm)/(2.0*delta)
    print ( "{:5d}{:>10}{:15.6f}{:15.6f}{:15.4e}".format(i,ct[xyz],t_exact,tnum,t_exact-tnum) )

