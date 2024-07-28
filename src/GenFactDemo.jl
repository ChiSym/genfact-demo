using Oxygen
using Base
using Mustache
using JSON3
using Logging
using HTTP
using Serialization
using PClean

const RESOURCES = "$(@__DIR__)/../resources" # grammar, database, etc.
const GENPARSE_INFERENCE_URL = "http://35.225.217.118:8888/infer"

include("genparse/genparse.jl")
include("pclean/pclean.jl")
include("app.jl")
