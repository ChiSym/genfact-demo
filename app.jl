using Oxygen
using HTTP
using JSON

@post "/form" function(req)
    return "this"
end

struct ToPCleanSentence
    sentence::String
end


#=
request = {
        "prompt": prompt,
        "method": "smc-standard",
        "n_particles": 10,
        "lark_grammar": grammar,
        "proposal_name": "character",
        "proposal_args": {},
        "max_tokens": 100,
        "temperature": 1.
        }
    headers = {
        "Content-type": "application/json",
        "Accept": "application/json"
        }
=#

PROMPT = ""
N_PARTICLES = 5
GRAMMAR = """ start: "Sequential Monte Carlo is " ("good" | "bad") """
URL = "http://34.122.30.137:8888/infer"

@post "/sentence-to-pclean" function(req)
    data = json(req, ToPCleanSentence)
    sentence = data.sentence

    data = Dict(
        "prompt" => PROMPT, # add sentence to prompt
        "method" => "smc-standard",
        "n_particles" => N_PARTICLES,
        "lark_grammar" => GRAMMAR,
        "proposal_name" => "character",
        "proposal_args" => Dict(),
        "max_tokens" => 100,
        "temperature" => 1.
    )
    # Convert the dictionary to JSON
    json_data = JSON.json(data)
    # Send the POST request
    response = HTTP.post(URL, ["Content-Type" => "application/json"], json_data)

    return String(response.body)
end

serve(port=8888, host="0.0.0.0")