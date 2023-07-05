########################################################################
#                        ___    _   _____________
#                       /   |  / | / /_  __/ ___/
#                      / /| | /  |/ / / /  \__ \
#                     / ___ |/ /|  / / /  ___/ /
#                    /_/  |_/_/ |_/ /_/  /____/
#
# Test one-dimensional time-dependent problems
#
########################################################################

import pytest
import numpy as np

import ants
from ants import timed1d, fixed1d
from tests import problems1d


@pytest.mark.slab1d
@pytest.mark.backward_euler
@pytest.mark.parametrize(("boundary"), [[0, 0], [1, 0], [0, 1]])
def test_reed_backward_euler(boundary):
    xs_total, xs_scatter, xs_fission, external, boundary_x, medium_map, \
        delta_x, angle_x, angle_w, info = problems1d.reeds(boundary)
    # Get Fixed Source
    fixed_flux = fixed1d.source_iteration(xs_total, xs_scatter, xs_fission, \
                                external, boundary_x, medium_map, delta_x, \
                                angle_x, angle_w, info)
    # Set time dependent variables
    info["steps"] = 100
    info["dt"] = 1.
    velocity = np.ones((info["groups"],))
    timed_flux = timed1d.backward_euler(xs_total, xs_scatter, xs_fission, \
                                velocity, external, boundary_x, medium_map, \
                                delta_x, angle_x, angle_w, info)
    assert np.isclose(fixed_flux[:,0], timed_flux[-1,:,0]).all(), \
        "Incorrect Flux"


@pytest.mark.sphere1d
@pytest.mark.backward_euler
@pytest.mark.multigroup1d
def test_sphere_01_backward_euler():
    info = problems1d.sphere_01("timed")[-1]
    flux = timed1d.backward_euler(*problems1d.sphere_01("timed"))
    reference = np.load(problems1d.PATH + "uranium_sphere_backward_euler_flux.npy")
    for tt in range(info["steps"]):
        assert np.isclose(flux[tt], reference[tt]).all()