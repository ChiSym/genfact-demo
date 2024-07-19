using Oxygen
using HTTP
using JSON3

@post "/form" function(req)
    return "this"
end

struct ToPCleanSentence
    sentence::String
end



N_PARTICLES = 5
GRAMMAR = """ start: "Sequential Monte Carlo is " ("good" | "bad") """
URL = "http://34.122.30.137:8888/infer"

@post "/sentence-to-pclean" function(request)
    data = JSON3.read(request.body)
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
    response = JSON3.read(response.body)

    response.posterior
end

@post "/run-pclean" function(request)
end

serve(port=8888, host="0.0.0.0")