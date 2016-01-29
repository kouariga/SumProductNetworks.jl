#addprocs(3)

using BNP
using SPN
using HSIC
using Base.Test
using Distributions

# run nodes tests
println("# starting: node tests...")
include("nodetests.jl")
println("# finished: node test.")

println("# starting: Gens structure learning tests...")
include("genstests.jl")
println("# finished: Gens structure learning tests.")

println("# starting: infinite SPN tests...")
include("infiniteSPNtests.jl")
println("# finished: infinite SPN tests...")
