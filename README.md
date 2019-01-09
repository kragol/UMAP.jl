# UMAP.jl (WIP)
[![Build Status](https://travis-ci.com/dillondaudert/UMAP.jl.svg?branch=master)](https://travis-ci.com/dillondaudert/UMAP.jl)[![Coverage Status](https://coveralls.io/repos/github/dillondaudert/UMAP.jl/badge.svg?branch=master)](https://coveralls.io/github/dillondaudert/UMAP.jl?branch=master) [![codecov](https://codecov.io/gh/dillondaudert/UMAP.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/dillondaudert/UMAP.jl)

A straightforward implementation of the [Uniform Manifold Approximation and Projection](https://arxiv.org/abs/1802.03426) dimension reduction
algorithm in Julia.

> McInnes, L, Healy, J, *UMAP: Uniform Manifold Approximation and Projection for
> Dimension Reduction*. ArXiV 1802.03426, 2018

## Usage
```jl
embedding = umap(X, n_components; n_neighbors, metric, min_dist, ...)
```
The `umap` function takes two arguments, `X` (a matrix of shape (n_features, n_samples)), `n_components` (the number of dimensions in the output embedding), and several keyword arguments:
- `n_neighbors::Int=15`: This controls how many neighbors around each point are considered to be part of its local neighborhood. Larger values will result in embeddings that capture more global structure, while smaller values will preserve more local structures.
- `metric::SemiMetric=Euclidean()`: The (semi)metric to use when calculating distances between points. This can be any subtype of the `SemiMetric` type from the `Distances.jl` package, including user-defined types.
- `min_dist::Float=0.1`: This controls the minimum spacing of points in the embedding. Larger values will cause points to be more evenly distributed, while smaller values will preserve more local structure.


## Examples
The full MNIST and FMNIST datasets are plotted below using both this implementation and the [Python implementation](github.com/lmcinnes/umap) for comparison. These were generated by [this notebook](PlotMNIST.ipynb).

Note that the memory allocation for the Python UMAP is unreliable, as Julia's benchmarking doesn't count memory allocated within Python itself.
### MNIST
![Julia MNIST](img/mnist_julia.png)
![Python MNIST](img/mnist_python.png)

### FMNIST
![Julia FMNIST](img/fmnist_julia.png)
![Python FMNIST](img/fmnist_python.png)

## Disclaimer
This implementation is a work-in-progress. If you encounter any issues, please create
an issue or make a pull request.
