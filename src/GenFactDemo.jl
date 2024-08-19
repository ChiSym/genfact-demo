module GenFactDemo

using Oxygen; @oxidise
using Base
using Mustache
using JSON3
using Logging
using HTTP
using Serialization
using PClean

const RESOURCES = "$(@__DIR__)/../resources" # grammar, database, etc.
const GENPARSE_INFERENCE_URL = "http://34.122.30.137:8888/infer"

include("genparse/genparse.jl")
using .Genparse
include("pclean/pclean.jl")
include("app.jl")

@get "/" hello_world
@post "/sentence-to-doctor-data" sentence_to_doctor_data
@post "/run-pclean" run_pclean

function main()
    global_logger()
    println("Starting server...")
    serve(host="0.0.0.0", port=8888)
end

end