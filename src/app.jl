@get "/" function(request)
    return "Hello :)"
end

@post "/sentence-to-pclean" function(request)
    data = json(request)
    sentence = data.sentence

    N_PARTICLES = 5

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

@get "/run_pclean" function(request)
    # trace, query, iterations = try
    data = json(request)
    # println(data)
    if !("observations" in keys(data))
        throw(PCleanException("\"observations\" not specified."))
    end
    iterations = 1000
    table = deserialize("$RESOURCES/database/physician.jls")
    trace = PClean.PCleanTrace(MODEL, table)
    query = generate_query(trace, data.observations)
    trace, query, iterations
    # catch e
        # return HTTP.Response(500, "Server error: $(string(e))")
    # end
    # println(query)
    # println()

    # try
    results = execute_query(trace, query, iterations)
    return results
end

function main(port=8888)
    load_database(RESOURCES)
    serve(port=port)
end