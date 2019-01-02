# an implementation of Uniform Manifold Approximation and Projection
# for Dimension Reduction, L. McInnes, J. Healy, J. Melville, 2018.

struct UMAP_{S, T}
    graph::AbstractMatrix{S}
    embedding::AbstractMatrix{T}
    
    function UMAP_(graph::AbstractMatrix{S}, embedding::AbstractMatrix{T}) where {S, T}
        issymmetric(graph) || throw(MethodError("UMAP_ constructor expected graph to be a symmetric matrix"))
        new{S, T}(graph, embedding)
    end
end

"""
    UMAP_(X[, n_neighbors=15, n_components=2]; <kwargs>)

Embed the data `X` into a `n_components`-dimensional space. `n_neighbors` controls
how many neighbors to consider as locally connected. Larger values capture more 
global structure in the data, while small values capture more local structure.

# Keyword Arguments
- `metric::SemiMetric = Euclidean()`: the metric to calculate distance in the input space
- `n_epochs::Integer = 300`: the number of training epochs for embedding optimization
- `learning_rate::AbstractFloat = 1.`: the initial learning rate during optimization
- `init::Symbol = :spectral`: how to initialize the output embedding; valid options 
are `:spectral` and `:random`
- `min_dist::AbstractFloat = 0.1`: the minimum spacing of points in the output embedding
- `spread::AbstractFloat = 1.0`: the effective scale of embedded points. Determines how
clustered embedded points are in combination with `min_dist`.
- `set_operation_ratio::AbstractFloat = 1.0`: interpolates between fuzzy set union and 
fuzzy set intersection when constructing the UMAP graph (global fuzzy simplicial set).
The value of this parameter should be between 1.0 and 0.0: 1.0 indicates pure fuzzy union,
while 0.0 indicates pure fuzzy intersection.
- `local_connectivity::Integer = 1`: the number of nearest neighbors that should be assumed
to be locally connected. The higher this value, the more connected the manifold becomes. This
should not be set higher than the intrinsic dimension of the manifold.
- `repulsion_strength::AbstractFloat = 1.0`: the weighting of negative samples during the
optimization process. 
- `neg_sample_rate::Integer = 5`: the number of negative samples to select for each positive 
sample. Higher values will increase computational cost but result in slightly more accuracy.
- `a::AbstractFloat = nothing`: this controls the embedding. By default, this is determined
automatically by `min_dist` and `spread`.
- `b::AbstractFloat = nothing`: this controls the embedding. By default, this is determined
automatically by `min_dist` and `spread`.
"""
function UMAP_(X::Vector{V},
               n_neighbors::Integer = 15,
               n_components::Integer = 2;
               metric::SemiMetric = Euclidean(),
               n_epochs::Integer = 300,
               learning_rate::AbstractFloat = 1.,
               init::Symbol = :spectral,
               min_dist::AbstractFloat = 0.1,
               spread::AbstractFloat = 1.0,
               set_operation_ratio::AbstractFloat = 1.0,
               local_connectivity::Integer = 1,
               repulsion_strength::AbstractFloat = 1.0,
               neg_sample_rate::Integer = 5,
               a::Union{AbstractFloat, Nothing} = nothing,
               b::Union{AbstractFloat, Nothing} = nothing
               ) where {V <: AbstractVector}
    # argument checking
    length(X) > n_neighbors > 0|| throw(ArgumentError("length(X) must be greater than n_neighbors and n_neighbors must be greater than 0"))
    length(X[1]) > n_components > 1 || throw(ArgumentError("n_components must be greater than 0 and less than the dimensionality of the data"))
    min_dist > 0. || throw(ArgumentError("min_dist must be greater than 0"))
    #n_epochs > 0 || throw(ArgumentError("n_epochs must be greater than 1"))
    

    # main algorithm
    umap_graph = fuzzy_simplicial_set(X, n_neighbors)

    embedding = simplicial_set_embedding(umap_graph, n_components, min_dist, n_epochs; 
                                         init=init, alpha=learning_rate, neg_sample_rate=neg_sample_rate)

    # TODO: if target variable y is passed, then construct target graph
    #       in the same manner and do a fuzzy simpl set intersection

    return UMAP_(umap_graph, embedding)
end

"""
    fuzzy_simpl_set(X, n_neighbors) -> graph::SparseMatrixCSC

Construct the local fuzzy simplicial sets of each point in `X` by
finding the approximate nearest `n_neighbors`, normalizing the distances
on the manifolds, and converting the metric space to a simplicial set.
"""
function fuzzy_simplicial_set(X, n_neighbors)
    #if length(X) < 4096:
        # compute all pairwise distances
    knngraph = DescentGraph(X, n_neighbors)
    knns = Array{Int}(undef, size(knngraph.graph))
    dists = Array{Float64}(undef, size(knngraph.graph))
    for index in CartesianIndices(knngraph.graph)
        @inbounds knns[index] = knngraph.graph[index][1]
        @inbounds dists[index] = knngraph.graph[index][2]
    end

    σs, ρs = smooth_knn_dists(dists, n_neighbors)

    rows, cols, vals = compute_membership_strengths(knns, dists, σs, ρs)
    fs_set = sparse(rows, cols, vals, size(knns)[2], size(knns)[2]) 
                                      # sparse matrix M[i, j] = vᵢⱼ where
                                      # vᵢⱼ is the probability that j is in the
                                      # simplicial set of i
    return dropzeros(fs_set .+ fs_set' .- fs_set .* fs_set')
end

"""
    smooth_knn_dists(dists, k; <kwargs>) -> knn_dists, nn_dists

Compute the distances to the nearest neighbors for a continuous value `k`. Returns
the approximated distances to the kth nearest neighbor (`knn_dists`)
and the nearest neighbor (nn_dists) from each point.

# Keyword Arguments
...
"""
function smooth_knn_dists(knn_dists::AbstractMatrix{S}, k::Integer;
                          niter::Integer=64,
                          local_connectivity::AbstractFloat=1.,
                          bandwidth::AbstractFloat=1.,
                          ktol = 1e-5) where {S <: Real}
    @inline minimum_nonzero(dists) = minimum(dists[dists .> 0.])
    ρs = S[minimum_nonzero(knn_dists[:, i]) for i in 1:size(knn_dists)[2]]
    σs = zeros(S, size(knn_dists)[2])

    for i in 1:size(knn_dists)[2]
        @inbounds σs[i] = smooth_knn_dist(knn_dists[:, i], k, niter, ρs[i], ktol)
    end
    return ρs, σs
end

@fastmath function smooth_knn_dist(dists::AbstractVector, k, niter, ρ, ktol)
    target = log2(k)
    lo, mid, hi = 0., 1., Inf
    #psum(dists, ρ) = sum(exp.(-max.(dists .- ρ, 0.)/mid))
    for n in 1:niter
        psum = sum(exp.(-max.(dists .- ρ, 0.)./mid))
        if abs(psum - target) < ktol
            break
        end
        if psum > target
            hi = mid
            mid = (lo + hi)/2.
        else
            lo = mid
            if hi == Inf
                mid *= 2.
            else
                mid = (lo + hi) / 2.
            end
        end
    end
    # TODO: set according to min k dist scale
    return mid
end

"""
    compute_membership_strengths(knns, dists, σ, ρ) -> rows, cols, vals

Compute the membership strengths for the 1-skeleton of each fuzzy simplicial set.
"""
function compute_membership_strengths(knns::AbstractMatrix{S}, 
                                      dists::AbstractMatrix{T}, 
                                      ρs::Vector{T}, 
                                      σs::Vector{T}) where {S <: Integer, T}
    # set dists[i, j]
    rows = sizehint!(S[], length(knns))
    cols = sizehint!(S[], length(knns))
    vals = sizehint!(T[], length(knns))
    for i in 1:size(knns)[2], j in 1:size(knns)[1]
        @inbounds if i == knns[j, i] # dist to self
            d = 0.
        else
            @inbounds d = exp(-max(dists[j, i] - ρs[i], 0.)/σs[i])
        end
        append!(cols, i)
        append!(rows, knns[j, i])
        append!(vals, d)
    end
    return rows, cols, vals
end

"""
    simplicial_set_embedding(graph, n_components, n_epochs; <kwargs>) -> embedding

Create an embedding by minimizing the fuzzy set cross entropy between the
fuzzy simplicial set 1-skeletons of the data in high and low dimensional
spaces.
"""
function simplicial_set_embedding(graph::SparseMatrixCSC, n_components, min_dist, n_epochs;
                                  init::Symbol=:spectral, alpha::AbstractFloat=1.0,
                                  neg_sample_rate::Integer=5)
    
    if init == :spectral
        X_embed = spectral_layout(graph, n_components)
        # expand 
        expansion = 10. / maximum(X_embed)
        @. X_embed = (X_embed*expansion) + randn(size(X_embed))*0.0001
    elseif init == :random
        print("using random initialization")
        X_embed = 20. .* rand(n_components, size(graph, 1)) .- 10.
    end
    # refine embedding with SGD
    X_embed = optimize_embedding(graph, X_embed, n_epochs, alpha, min_dist, 1.0; neg_sample_rate=neg_sample_rate)
    
    return X_embed
end

"""
    optimize_embedding(graph, embedding, min_dist, spread, alpha, n_epochs) -> embedding

Optimize an embedding by minimizing the fuzzy set cross entropy between the high and low
dimensional simplicial sets using stochastic gradient descent.

# Arguments
- `graph`: a sparse matrix of shape (n_samples, n_samples)
- `embedding`: a dense matrix of shape (n_components, n_samples)
# Keyword Arguments
- `neg_sample_rate::Integer=5`: the number of negative samples per positive sample
"""
function optimize_embedding(graph, embedding, n_epochs, initial_alpha, min_dist, spread;
                            neg_sample_rate::Integer=5)
    a, b = fit_ϕ(min_dist, spread)

    clip(x) = x < -4. ? -4. : (x > 4. ? 4. : x)
    grad = Array{eltype(embedding)}(undef, size(embedding[:,1]))
    alpha = initial_alpha
    for e in 1:n_epochs

        @views @fastmath @inbounds for i in 1:size(graph)[2]
            for ind in nzrange(graph, i)
                j = rowvals(graph)[ind]
                p = nonzeros(graph)[ind]
                if rand() <= p
                    # calculate distance between embedding[:, i] and embedding[:, j]
                    sdist = sum((embedding[:, i] .- embedding[:, j]).^2)
                    if sdist > 0.
                        delta = (-2. * a * b * sdist^(b-1))/(1. + a*sdist^b)
                    else
                        delta = 0.
                    end
                    grad .= clip.(delta .* (embedding[:, i] .- embedding[:, j]))
                    embedding[:, i] .+= alpha .* grad
                    embedding[:, j] .-= alpha .* grad 

                    for _ in 1:neg_sample_rate
                        k = rand(1:size(graph)[2])
                        sdist = sum((embedding[:, i] .- embedding[:, k]).^2)
                        if sdist > 0
                            delta = (2. * b) / (0.001 + sdist)*(1. + a*sdist^b)
                        elseif i == k
                            continue
                        else
                            delta = 0.
                        end
                        # set negative gradients to positive 4.
                        if delta > 0.
                            grad .= clip.(delta .* (embedding[:,i] - embedding[:, k]))
                        else
                            grad .= 4.
                        end
                        embedding[:, i] .+= alpha .* grad
                    end

                end
            end
        end
        alpha = initial_alpha*(1. - e/n_epochs)
    end

    return embedding
end

"""
    fit_ϕ(min_dist, spread) -> a, b

Find a smooth approximation to the membership function of points embedded in ℜᵈ.
This fits a smooth curve that approximates an exponential decay offset by `min_dist`.
"""
function fit_ϕ(min_dist, spread)
    ψ(d) = d > 0. ? exp(-(d - min_dist)/spread) : 1.
    xs = LinRange(0., spread*3, 300)
    ys = map(ψ, xs)
    @. curve(x, p) = (1. + p[1]*x^(2*p[2]))^(-1)
    result = curve_fit(curve, xs, ys, [1., 1.])
    a, b = result.param
    return a, b
end

"""
    spectral_layout(graph, embed_dim) -> embedding

Initialize the graph layout with spectral embedding.
"""
function spectral_layout(graph::SparseMatrixCSC{T}, embed_dim::Integer) where {T<:AbstractFloat}
    D_ = Diagonal(dropdims(sum(graph; dims=2); dims=2))
    D = inv(sqrt(D_))
    # normalized laplacian
    # TODO: remove sparse() when PR #30018 is merged
    L = sparse(Symmetric(I - D*graph*D))

    k = embed_dim+1
    num_lanczos_vectors = max(2k+1, round(Int, sqrt(size(L)[1])))
    local layout
    try
        # get the 2nd - embed_dim+1th smallest eigenvectors
        eigenvals, eigenvecs = eigs(L; nev=k,
                                       ncv=num_lanczos_vectors,
                                       which=:SM,
                                       tol=1e-4,
                                       v0=ones(size(L)[1]),
                                       maxiter=size(L)[1]*5)
        layout = permutedims(eigenvecs[:, 2:k])::Array{T, 2}
    catch e
        print(e)
        print("Error occured in spectral_layout;
               falling back to random layout.")
        layout = 20 .* rand(T, embed_dim, size(L)[1]) .- 10
    end
    return layout
end
