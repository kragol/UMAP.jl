@testset "utils tests" begin
    @testset "pairwise_knn tests" begin
        data = [0. 0. 0.; 0. 1.5 2.]
        true_knns = [2 3 2; 3 1 1]
        true_dists = [1.5 .5 .5; 2. 1.5 2.]
        knns, dists = pairwise_knn(data, 2, Euclidean())
        @test knns == true_knns
        @test dists == true_dists
    end
    
    @testset "combine_fuzzy_sets tests" begin
        A = [1.0 0.1; 0.4 1.0]
        union_res = [1.0 0.46; 0.46 1.0]
        res = combine_fuzzy_sets(A, 1.0)
        @test isapprox(res, union_res)
        inter_res = [1.0 0.04; 0.04 1.0]
        res = combine_fuzzy_sets(A, 0.0) 
        @test isapprox(res, inter_res)
        
    end
end