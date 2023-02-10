########################################################################
#                        ___    _   _____________
#                       /   |  / | / /_  __/ ___/
#                      / /| | /  |/ / / /  \__ \ 
#                     / ___ |/ /|  / / /  ___/ / 
#                    /_/  |_/_/ |_/ /_/  /____/  
#
# Functions needed for both fixed source, criticality, and 
# time-dependent problems in one-dimensional neutron transport 
#
########################################################################

# cython: boundscheck=False
# cython: nonecheck=False
# cython: wraparound=False
# cython: infertypes=True
# cython: initializedcheck=False
# cython: cdivision=True
# distutils: language = c++

# cython: profile=True

from libc.math cimport sqrt, pow
from cython.view cimport array as cvarray
import numpy as np

cdef params1d _to_params1d(dict params_dict):
    cdef params1d params
    params.cells = params_dict["cells"]
    params.angles = params_dict["angles"]
    params.groups = params_dict["groups"]
    params.materials = params_dict["materials"]
    params.geometry = params_dict["geometry"] 
    params.spatial = params_dict["spatial"]
    params.qdim = params_dict["qdim"]
    params.bc = params_dict["bc"]
    params.bcdim = params_dict["bcdim"]
    params.steps = params_dict["steps"]
    params.dt = params_dict["dt"]
    params.angular = params_dict["angular"]
    params.adjoint = params_dict["adjoint"]
    return params

cdef void combine_self_scattering(double[:,:,:]& xs_matrix, \
                    double[:,:,:]& xs_scatter, double[:,:,:]& xs_fission, \
                    params1d params):
    cdef size_t mat, ig, og
    for mat in range(params.materials):
        for ig in range(params.groups):
            for og in range(params.groups):
                xs_matrix[mat][ig][og] = xs_scatter[mat][ig][og] \
                                            + xs_fission[mat][ig][og]

cdef void combine_total_velocity(double[:,:]& xs_total_star, \
            double[:,:]& xs_total, double[:]& velocity, params1d params):
    cdef size_t mat, group
    for group in range(params.groups):
        for mat in range(params.materials):
            xs_total_star[mat,group] = xs_total[mat,group] \
                                    + 1 / (velocity[group] * params.dt)

# Work on this
cdef void combine_source_flux(double[:,:,:]& flux_last, double[:]& source_star, \
                double[:]& source, double[:]& velocity, params1d params):
    cdef size_t cell, angle, group
    cdef size_t skip = params.groups * params.angles
    for group in range(params.groups):
        for angle in range(params.angles):
            for cell in range(params.cells):
                source_star[group+angle*params.groups::skip][cell] \
                    = source[group+angle*params.groups::skip][cell] \
                        + flux_last[cell,angle,group] \
                        * 1 / (velocity[group] * params.dt)

cdef double[:] array_1d_i(params1d params):
    dd1 = cvarray((params.cells,), itemsize=sizeof(double), format="d")
    cdef double[:] flux = dd1
    flux[:] = 0.0
    return flux

cdef double[:] array_1d_ig(params1d params):
    dd1 = cvarray((params.cells * params.groups,), \
                    itemsize=sizeof(double), format="d")
    cdef double[:] flux = dd1
    flux[:] = 0.0
    return flux

cdef double[:] array_1d_ing(params1d params):
    dd1 = cvarray((params.cells * params.angles * params.groups,), \
                    itemsize=sizeof(double), format="d")
    cdef double[:] flux = dd1
    flux[:] = 0.0
    return flux

cdef double[:,:] array_2d_ig(params1d params):
    dd1 = cvarray((params.cells, params.groups), itemsize=sizeof(double), format="d")
    cdef double[:,:] flux = dd1
    flux[:,:] = 0.0
    return flux

cdef double[:,:] array_2d_in(params1d params):
    dd1 = cvarray((params.cells, params.angles), itemsize=sizeof(double), format="d")
    cdef double[:,::1] flux = dd1
    flux[:,:] = 0.0
    return flux

cdef double[:,:,:] array_3d_ing(params1d params):
    dd1 = cvarray((params.cells, params.angles, params.groups), \
                    itemsize=sizeof(double), format="d")
    cdef double[:,:,:] flux = dd1
    flux[:,:,:] = 0.0
    return flux

cdef double[:,:,:] array_3d_mgg(params1d params):
    dd1 = cvarray((params.materials, params.groups, params.groups), \
                    itemsize=sizeof(double), format="d")
    cdef double[:,:,:] flux = dd1
    flux[:,:,:] = 0.0
    return flux

cdef double[:,:,:,:] array_4d_ting(params1d params):
    dd1 = cvarray((params.steps, params.cells, params.angles, params.groups), \
                    itemsize=sizeof(double), format="d")
    cdef double[:,:,:,:] flux = dd1
    flux[:,:,:,:] = 0.0
    return flux

cdef double group_convergence_scalar(double[:,:]& arr1, double[:,:]& arr2, \
                                params1d params):
    cdef size_t cell, group
    cdef double change = 0.0
    for group in range(params.groups):
        for cell in range(params.cells):
            change += pow((arr1[cell][group] - arr2[cell][group]) \
                         / arr1[cell][group] / params.cells, 2)
    change = sqrt(change)
    return change

cdef double group_convergence_angular(double[:,:,:]& arr1, \
                double[:,:,:]& arr2, double[:]& weight, params1d params):
    cdef size_t group, cell, angle
    cdef double change = 0.0
    cdef double flux, flux_old
    for group in range(params.groups):
        for cell in range(params.cells):
            flux = 0.0
            flux_old = 0.0
            for angle in range(params.angles):
                flux += arr1[cell, angle, group] * weight[angle] 
                flux_old += arr2[cell, angle, group] * weight[angle]
            change += pow((flux - flux_old) / flux / params.cells, 2)
    change = sqrt(change)
    return change

cdef double[:] angle_flux(params1d params, bint angular):
    cdef int flux_size
    if angular == True:
        flux_size = params.cells * params.angles
    else:
        flux_size = params.cells
    dd1 = cvarray((flux_size,), itemsize=sizeof(double), format="d")
    cdef double[:] flux = dd1
    flux[:] = 0.0
    return flux

cdef void angle_angular_to_scalar(double[:,:]& angular, double[:]& scalar, \
                                  double[:]& weight, params1d params):
    cdef size_t cell, angle
    scalar[:] = 0.0
    for angle in range(params.angles):
        for cell in range(params.cells):
            scalar[cell] += weight[angle] * angular[cell,angle]

cdef double angle_convergence_angular(double[:,:]& arr1, double[:,:]& arr2, \
                                double[:]& weight, params1d params):
    cdef size_t cell, angle
    cdef double change = 0.0
    cdef double flux, flux_old
    for cell in range(params.cells):
        flux = 0.0
        flux_old = 0.0
        for angle in range(params.angles):
            flux += weight[angle] * arr1[cell,angle]
            flux_old += weight[angle] * arr2[cell,angle]
        change += pow((flux - flux_old) / flux / params.cells, 2)
    change = sqrt(change)
    return change

cdef double angle_convergence_scalar(double[:]& arr1, double[:]& arr2, \
                                params1d params):
    cdef size_t cell
    cdef double change = 0.0    
    for cell in range(params.cells):
        change += pow((arr1[cell] - arr2[cell]) / arr1[cell] / params.cells, 2)
    change = sqrt(change)
    return change

cdef void off_scatter_scalar(double[:,:]& flux, double[:,:]& flux_old, \
            int[:]& medium_map, double[:,:,:]& xs_matrix, double[:]& source, \
            params1d params, size_t group):
    cdef size_t cell, mat, angle, og
    source[:] = 0.0
    for cell in range(params.cells):
        mat = medium_map[cell]
        for og in range(0, group):
            source[cell] += xs_matrix[mat,group,og] * flux[cell,og]
        for og in range(group+1, params.groups):
            source[cell] += xs_matrix[mat,group,og] * flux_old[cell,og]

cdef void off_scatter_angular(double[:,:,:]& flux, double[:,:,:]& flux_old, \
            int[:]& medium_map, double[:,:,:]& xs_matrix, double[:]& source, \
            double[:]& weight, params1d params, size_t group):
    cdef size_t cell, mat, angle, og
    source[:] = 0.0
    for cell in range(params.cells):
        mat = medium_map[cell]
        for angle in range(params.angles):
            for og in range(0, group):
                source[cell] += xs_matrix[mat,group,og] * weight[angle] \
                                * flux[cell,angle,og]
            for og in range(group+1, params.groups):
                source[cell] += xs_matrix[mat,group,og] * weight[angle] \
                                * flux_old[cell,angle,og]

cdef void fission_source(double[:,:] flux, double[:,:,:] xs_fission, \
                    double[:] power_source, int[:] medium_map, \
                    params1d params, double keff):
    power_source[:] = 0.0
    cdef size_t cell, mat, ig, og
    for cell in range(params.cells):
        mat = medium_map[cell]
        for ig in range(params.groups):
            for og in range(params.groups):
                power_source[ig::params.groups][cell] += (1 / keff) \
                            * flux[cell,og] * xs_fission[mat,ig,og]

cdef void normalize_flux(double[:,:]& flux, params1d params):
    cdef size_t cell, group
    cdef double keff = 0.0
    for group in range(params.groups):
        for cell in range(params.cells):
            keff += pow(flux[cell,group], 2)
    keff = sqrt(keff)
    for group in range(params.groups):
        for cell in range(params.cells):
            flux[cell,group] /= keff

cdef double update_keffective(double[:,:] flux, double[:,:] flux_old, \
                            double[:,:,:] xs_fission, int[:] medium_map, \
                            params1d params, double keff_old):
    cdef double rate_new = 0.0
    cdef double rate_old = 0.0
    cdef size_t cell, mat, ig, og
    for cell in range(params.cells):
        mat = medium_map[cell]
        for ig in range(params.groups):
            for og in range(params.groups):
                rate_new += flux[cell,og] * xs_fission[mat][ig][og]
                rate_old += flux_old[cell,og] * xs_fission[mat][ig][og]
    return (rate_new * keff_old) / rate_old

cdef void nearby_fission_source(double[:,:]& flux, double[:,:,:]& xs_fission, \
                        double[:]& power_source, double[:]& nearby_source, \
                        int[:]& medium_map, params1d params, double keff):
    power_source[:] = 0.0
    cdef size_t cell, mat, angle, ig, og, skip
    skip = params.angles * params.groups
    for cell in range(params.cells):
        mat = medium_map[cell]
        for angle in range(params.angles):
            for ig in range(params.groups):
                for og in range(params.groups):
                    power_source[ig+angle*params.groups::skip][cell] += \
                            flux[cell,og] * xs_fission[mat,ig,og] / keff
    for cell in range(params.cells * skip):
        power_source[cell] += nearby_source[cell]

cdef double nearby_keffective(double[:,:]& flux, double rate, params1d params):
    cdef size_t cell, group
    cdef double keff = 0.0
    for cell in range(params.cells):
        for group in range(params.groups):
            keff += rate * flux[cell,group]
    return keff

cdef void calculate_source_c(double[:,:]& flux_u, double[:,:,:]& xs_scatter_u, \
                double[:]& source_c, int[:]& medium_map, int[:]& index_c, \
                params1d params_u, params1d params_c):
    cdef size_t cell, mat, angle, group, ig, og
    # Multiply flux by scatter
    flux = flux_u.copy()
    for cell in range(params_u.cells):
        mat = medium_map[cell]
        for ig in range(params_u.groups):
            for og in range(params_u.groups):
                flux[cell,og] *=  xs_scatter_u[mat,ig,og]
    # Shrink to size G hat
    big_to_small(flux, source_c, index_c, params_u, params_c)

cdef void calculate_source_t(double[:,:]& flux_u, double[:,:]& flux_ch, \
                double[:,:,:]& xs_scatter_u, double[:]& source_t, \
                int[:]& medium_map, int[:]& index_u, double[:]& factor_u, \
                params1d params_u, params1d params_c):
    cdef size_t cell, mat, angle, group, ig, og
    source_t[:] = 0.0
    # Resize collided flux to size (I x G)
    # flux_c = small_to_big(flux_ch, index_u, factor_u, params_u, params_c)
    flux_c = flux_ch[:,:]
    # Add collided and uncollided together
    for cell in range(params_u.cells):
        for group in range(params_u.groups):
            source_t[group::params_u.groups][cell] = flux_u[cell,group] + flux_c[cell,group]
    # Multiply flux by scatter
    # print("sum flux", np.sum(source_t))
    for cell in range(params_u.cells):
        mat = medium_map[cell]
        for ig in range(params_u.groups):
            for og in range(params_u.groups):
                source_t[og::params_u.groups][cell] *= xs_scatter_u[mat,ig,og]

cdef void calculate_source_star(double[:,:,:]& flux_last, double[:]& source_star, \
        double[:]& source_t, double[:]& source_u, double[:]& velocity, params1d params):
    cdef size_t cell, angle, group
    cdef size_t skip = params.groups * params.angles
    source_star[:] = 0.0
    for group in range(params.groups):
        for angle in range(params.angles):
            for cell in range(params.cells):
                source_star[angle::params.angles][cell] = source_t[cell] \
                        + source_u[angle::params.angles][cell] \
                        + flux_last[cell,angle,group] \
                        * 1 / (velocity[group] * params.dt)

                    # = source_t[group::params.groups][cell] \
                    #     + source_u[group+angle*params.groups::skip][cell] \
                    #     + flux_last[cell,angle,group] \
                    #     * 1 / (velocity[group] * params.dt)

cdef void big_to_small(double[:,:]& flux_u, double[:]& flux_c, \
                int[:]& index_c, params1d params_u, params1d params_c):
    cdef size_t cell, group
    flux_c[:] = 0.0
    for cell in range(params_u.cells):
        for group in range(params_u.groups):
            # flux_c[cell, index_c[group]] += flux_u[cell,group]
            flux_c[index_c[group]::params_c.groups][cell] += flux_u[cell,group]

cdef double[:,:] small_to_big(double[:,:]& flux_c, int[:]& index_u, \
            double[:]& factor_u, params1d params_u, params1d params_c):
    cdef size_t cell, group_u, group_c
    flux_u = array_2d_ig(params_u)
    for cell in range(params_c.cells):
        for group_c in range(params_c.groups):
            for group_u in range(index_u[group_c], index_u[group_c+1]):
                flux_u[cell,group_u] = flux_c[cell,group_c] * factor_u[group_u]
    return flux_u[:,:]

# def big_2_small(big, fine, coarse, index_collided):
#     small = np.zeros((cells, coarse))
#     for cell in range(cells):
#         for group in range(fine):
#             small[cell, index_collided[group]] += big[cell,group]
#             # small[index_collided[group]::coarse][cell] += big[group::fine][cell]
#     return small

# def small_2_big(small, fine, coarse, index_uncollided, hybrid_factor):
#     big = np.zeros((cells, fine))
#     for cell in range(cells):
#         for group in range(coarse):
#             for group_u in range(index_uncollided[group], index_uncollided[group+1]):
#                 big[cell, group_u] = small[cell,group] * hybrid_factor[group_u]
#                 # big[group_u::fine][cell] = small[group::coarse][cell] * hybrid_factor[group_u]
#     return big

# index_collided = index_collided_calc(fine, idx)
# hybrid_factor = hybrid_factor_calc(fine, coarse, delta_u, delta_c, idx)
# index_uncollided = index_uncollided_calc(coarse, idx)

# collided_test = big_2_small(uncollided, fine, coarse, index_collided)
# uncollided_test = small_2_big(collided_test, fine, coarse, \
#                             index_uncollided, hybrid_factor)