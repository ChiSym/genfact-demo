module GenFactDemo
using Mustache
using Oxygen
using JSON3
using HTTP
using Serialization
using PClean
using JSON3


const RESOURCES = "./resources" # grammar, database, etc.
const URL = "http://34.122.30.137:8888/infer"

include("generate_pclean.jl")
include("query.jl")
include("init.jl")
include("app.jl")

const MODEL, TRACE = load_database(RESOURCES)

main()
end