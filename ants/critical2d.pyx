########################################################################
#                        ___    _   _____________
#                       /   |  / | / /_  __/ ___/
#                      / /| | /  |/ / / /  \__ \ 
#                     / ___ |/ /|  / / /  ___/ / 
#                    /_/  |_/_/ |_/ /_/  /____/  
#
# Two-Dimensional Criticality Multigroup Neutron Transport Problems
#
########################################################################

# cython: boundscheck=False
# cython: nonecheck=False
# cython: wraparound=False
# cython: infertypes=True
# cython: initializedcheck=False
# cython: cdivision=True
# cython: profile=True
# distutils: language = c++

import numpy as np

from ants cimport multi_group_2d as mg
from ants cimport cytools_2d as tools
from ants.parameters cimport params
from ants cimport parameters


def power_iteration(double[:,:] xs_total, double[:,:,:] xs_scatter, \
        double[:,:,:] xs_fission, int[:,:] medium_map, double[:] delta_x, \
        double[:] delta_y, double[:] angle_x, double[:] angle_y, \
        double[:] angle_w, dict params_dict):
    
    # Convert dictionary to type params1d
    info = parameters._to_params(params_dict)
    parameters._check_critical2d_power_iteration(info)
    
    # Initialize keff
    cdef double keff[1]
    keff[0] = 0.95
    
    # Initialize and normalize flux
    flux_old = np.random.rand(info.cells_x, info.cells_y, info.groups)
    tools._normalize_flux(flux_old, info)
    
    # Solve using the power iteration
    flux = multigroup_power(flux_old, xs_total, xs_scatter, xs_fission, \
                            medium_map, delta_x, delta_y, angle_x, \
                            angle_y, angle_w, info, keff)    
    if (info.angular == False) and (params_dict.get("edges", 0) == 0):
        return np.asarray(flux), keff[0]
    
    # For returning angular flux or flux at cell edges
    return known_source_calculation(flux, xs_total, xs_scatter, xs_fission, \
                    medium_map, delta_x, delta_y, angle_x, angle_y, angle_w, \
                    keff[0], params_dict), keff[0]


cdef double[:,:,:] multigroup_power(double[:,:,:]& flux_guess, \
        double[:,:]& xs_total, double[:,:,:]& xs_scatter, \
        double[:,:,:]& xs_fission, int[:,:]& medium_map, double[:]& delta_x, \
        double[:]& delta_y, double[:]& angle_x, double[:]& angle_y, \
        double[:]& angle_w, params info, double[:]& keff):
    
    # Initialize flux
    flux = tools.array_3d(info.cells_x, info.cells_y, info.groups)
    flux_old = flux_guess.copy()
    
    # Initialize power source
    source = tools.array_4d(info.cells_x, info.cells_y, 1, info.groups)
    
    # Vacuum boundaries
    boundary_x = tools.array_4d(2, 1, 1, 1)
    boundary_y = tools.array_4d(2, 1, 1, 1)
    
    # Set convergence limits
    cdef bint converged = False
    cdef int count = 1
    cdef double change = 0.0

    # Iterate until convergence
    while not (converged):
        
        # Update power source term
        tools._fission_source(flux_old, xs_fission, source, medium_map, \
                              info, keff[0])

        # Solve for scalar flux
        flux = mg.multi_group(flux_old, xs_total, xs_scatter, source, \
                            boundary_x, boundary_y, medium_map, delta_x, \
                            delta_y, angle_x, angle_y, angle_w, info)

        # Calculate k-effective
        keff[0] = tools._update_keffective(flux, flux_old, xs_fission, \
                                           medium_map, info, keff[0])
        tools._normalize_flux(flux, info)

        # Check for convergence
        change = tools.group_convergence(flux, flux_old, info)
        print("Count: {:>3}\tKeff: {:.8f}".format(str(count).zfill(3), \
                keff[0]), end="\r")
        converged = (change < info.change_keff) or (count >= info.count_keff)
        count += 1

        # Update old flux
        flux_old[:,:,:] = flux[:,:,:]

    print("\nConvergence: {:2.6e}".format(change))
    return flux[:,:,:]


def known_source_calculation(double[:,:,:] flux, double[:,:] xs_total, \
        double[:,:,:] xs_scatter, double[:,:,:] xs_fission, \
        int[:,:] medium_map, double[:] delta_x, double[:] delta_y, \
        double[:] angle_x, double[:] angle_y, double[:] angle_w, \
        double keff, dict params_dict):
    
    # Covert dictionary to type params
    info = parameters._to_params(params_dict)
    
    # Create (sigma_s + sigma_f) * phi + external function
    source = tools.array_4d(info.cells_x, info.cells_y, 1, info.groups)
    tools._source_total_critical(source, flux, xs_scatter, xs_fission, \
                                 medium_map, keff, info)

    # Vacuum boundaries
    boundary_x = tools.array_4d(2, 1, 1, 1)
    boundary_y = tools.array_4d(2, 1, 1, 1)

    # Return scalar flux cell edges
    if (info.angular == False) and (info.edges == 1):
        scalar_flux = mg._known_source_scalar(xs_total, source, boundary_x, \
                                boundary_y, medium_map, delta_x, delta_y, \
                                angle_x, angle_y, angle_w, info)
        return np.asarray(scalar_flux)
    
    # Solve for angular flux 
    angular_flux = mg._known_source_angular(xs_total, source, boundary_x, \
                                boundary_y, medium_map, delta_x, delta_y, \
                                angle_x, angle_y, angle_w, info)
    
    # Return angular flux (either edges or centers)
    return np.asarray(angular_flux)


def nearby_power(double[:,:] xs_total, double[:,:,:] xs_scatter, \
        double[:,:,:] xs_fission, double[:,:,:,:] residual, \
        int[:,:] medium_map, double[:] delta_x, double[:] delta_y, \
        double[:] angle_x, double[:] angle_y, double[:] angle_w, \
        double n_rate, dict params_dict):
    
    # Convert dictionary to type params1d
    info = parameters._to_params(params_dict)
    parameters._check_critical2d_nearby_power(info)
    
    # Initialize flux
    flux_old = np.random.rand(info.cells_x, info.cells_y, info.groups)
    tools._normalize_flux(flux_old, info)

    # Initialize keffective
    cdef double keff[1]
    
    # Initialize half step keffective for nearby problems
    keff[0] = tools._nearby_keffective(flux_old, n_rate, info)
    
    # Solve using the modified power iteration
    flux = multigroup_nearby(flux_old, xs_total, xs_scatter, xs_fission, \
                             residual, medium_map, delta_x, delta_y, \
                             angle_x, angle_y, angle_w, info, keff)
    
    return np.asarray(flux), keff[0]


cdef double[:,:,:] multigroup_nearby(double[:,:,:]& flux_guess, \
        double[:,:]& xs_total, double[:,:,:]& xs_scatter, \
        double[:,:,:]& xs_fission, double[:,:,:,:]& residual, \
        int[:,:]& medium_map, double[:]& delta_x, double[:]& delta_y, \
        double[:]& angle_x, double[:]& angle_y, double[:]& angle_w, \
        params info, double[:]& keff):

    # Initialize flux
    flux = tools.array_3d(info.cells_x, info.cells_y, info.groups)
    flux_old = flux_guess.copy()

    # Initialize power source
    fission_source = tools.array_4d(info.cells_x, info.cells_y, 1, info.groups)
    
    # Vacuum boundaries
    boundary_x = tools.array_4d(2, 1, 1, 1)
    boundary_y = tools.array_4d(2, 1, 1, 1)
    
    # Set convergence limits
    cdef bint converged = False
    cdef int count = 1
    cdef double change = 0.0

    # Iterate until converged
    while not (converged):
        # Update nearby power source term
        tools._nearby_fission_source(flux_old, xs_fission, fission_source, \
                                     residual, medium_map, info, keff[0])
        
        # Solve for scalar flux
        flux = mg.multi_group(flux_old, xs_total, xs_scatter, fission_source, \
                            boundary_x, boundary_y, medium_map, delta_x, \
                            delta_y, angle_x, angle_y, angle_w, info)
        
        # Update keffective
        keff[0] = tools._update_keffective(flux, flux_old, xs_fission, \
                                           medium_map, info, keff[0])
        
        # Normalize flux
        tools._normalize_flux(flux, info)
        
        # Check for convergence
        change = tools.group_convergence(flux, flux_old, info)
        print("Count: {:>3}\tKeff: {:.8f}".format(str(count).zfill(3), \
                keff[0]), end="\r")
        converged = (change < info.change_keff) or (count >= info.count_keff)
        count += 1

        # Update old flux
        flux_old[:,:,:] = flux[:,:,:]
    
    print("\nConvergence: {:2.6e}".format(change))
    return flux[:,:,:]
