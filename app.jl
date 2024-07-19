using Oxygen
using HTTP
using JSON3

include("pclean.jl")

const N_PARTICLES = 5
const GRAMMAR = """ start: "Sequential Monte Carlo is " ("good" | "bad") """
const URL = "http://34.122.30.137:8888/infer"

TRACE = load_database()

@post "/sentence-to-pclean" function(request)
    data = json(request)
    if !("sentence" in keys(data))
        println("error here...")
    end
    sentence = data.sentence

    genparse_params = Dict(
        "prompt" => "", # add sentence to prompt
        "method" => "smc-standard",
        "n_particles" => N_PARTICLES,
        "lark_grammar" => GRAMMAR,
        "proposal_name" => "character",
        "proposal_args" => Dict(),
        "max_tokens" => 100,
        "temperature" => 1.
    )
    json_data = JSON3.write(genparse_params)

    response = HTTP.post(URL, ["Content-Type" => "application/json"], json_data)
    response = json(response)

    response.posterior
end

@post "/run-pclean" function(request)
    data = json(request)
    query_pclean(data.pclean)
end

function main()
    serve(port=8888, host="0.0.0.0")
end

main()