
include("../find_2approx.jl")

using Base.Test



cores = [ CPU(0, 0, 0.0), CPU(0, 1, 0.0), CPU(0, 2, 0.0) ]
println(partition_cores(cores))

cores = [ CPU(0, 0, 0.0), CPU(0, 1, 0.0), CPU(0, 3, 0.0) ]
res = partition_cores(cores)
println(res)
@test res[1][1].pid == 0
@test res[1][2].pid == 1
@test res[2][1].pid == 3

cores = [ CPU(0, 3, 0.0) ]
println(partition_cores(cores))

cores = [ CPU(0, 3, 0.0), CPU(0, 4, 0.0) ]
println(partition_cores(cores))

cores = [ CPU(0, 3, 0.0), CPU(0, 5, 0.0) ]
println(partition_cores(cores))

