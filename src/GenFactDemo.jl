using Oxygen
using Base
using Mustache
using JSON3
using Logging
using HTTP
using PyCall
using Serialization
using PClean

const RESOURCES = "$(@__DIR__)/../resources" # grammar, database, etc.
const GENPARSE_INFERENCE_URL = "http://34.122.30.137:8888/infer"

include("genparse/genparse.jl")
include("pclean/pclean.jl")
include("app.jl")
