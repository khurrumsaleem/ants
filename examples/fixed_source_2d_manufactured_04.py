########################################################################
#                        ___    _   _____________
#                       /   |  / | / /_  __/ ___/
#                      / /| | /  |/ / / /  \__ \ 
#                     / ___ |/ /|  / / /  ___/ / 
#                    /_/  |_/_/ |_/ /_/  /____/  
# 
########################################################################

import ants
from ants.fixed2d import source_iteration
from ants.utils import manufactured_2d as mms

import numpy as np
import matplotlib.pyplot as plt
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--cells", type=int)
args = parser.parse_args()

cells_x = args.cells
cells_y = args.cells
angles = angles1 = 4
groups = 1

length_x = 2.
delta_x = np.repeat(length_x / cells_x, cells_x)
edges_x = np.linspace(0, length_x, cells_x+1)
centers_x = 0.5 * (edges_x[1:] + edges_x[:-1])

length_y = 2.
delta_y = np.repeat(length_y / cells_y, cells_y)
edges_y = np.linspace(0, length_y, cells_y+1)
centers_y = 0.5 * (edges_y[1:] + edges_y[:-1])

bc = [0, 0]

info = {
            "cells_x": cells_x,
            "cells_y": cells_y,
            "angles": angles, 
            "groups": groups, 
            "materials": 1,
            "geometry": 1, 
            "spatial": 2, 
            "bc_x": bc,
            "bc_y": bc,
            "angular": False
        }

xs_total = np.array([[1.0]])
xs_scatter = np.array([[[0.5]]])
xs_fission = np.array([[[0.0]]])

# Angular
angle_x, angle_y, angle_w = ants.angular_xy(info)

medium_map = np.zeros((cells_x, cells_y), dtype=np.int32)

# Externals
external = ants.external2d.manufactured_ss_04(centers_x, centers_y, \
                                                angle_x, angle_y)
boundary_x, boundary_y = ants.boundary2d.manufactured_ss_04(centers_x, \
                                        centers_y, angle_x, angle_y)

flux = source_iteration(xs_total, xs_scatter, xs_fission, external, \
                        boundary_x, boundary_y, medium_map, delta_x, \
                        delta_y, angle_x, angle_y, angle_w, info)
exact = mms.solution_ss_04(centers_x, centers_y, angle_x, angle_y)
exact_scalar = np.sum(exact * angle_w[None,None,:,None], axis=(2,3))

