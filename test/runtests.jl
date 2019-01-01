using Test
using SparseArrays
using LinearAlgebra
using UMAP: compute_membership_strengths, smooth_knn_dists, smooth_knn_dist, spectral_layout, optimize_embedding

include("umap_tests.jl")