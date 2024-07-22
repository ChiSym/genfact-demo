# module GenFactDemo
using Oxygen
using Mustache
using JSON3
using HTTP
using Serialization
using PClean
using JSON3

const RESOURCES = "$(@__DIR__)/../resources" # grammar, database, etc.
const URL = "http://34.122.30.137:8888/infer"

include("genparse/genparse.jl")
include("pclean/pclean.jl")
include("app.jl")

# export main
# end
main()