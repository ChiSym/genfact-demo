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

@post "/run-pclean" function(request)
    observations = try
        data = json(request)
        if !("observations" in keys(data))
            return HTTP.Response(400, "observations not specified")
        end
        data.observations
    catch e
        return HTTP.Response(500, "Server error")
    end

    query = try
        generate_query(observations)
    catch e
        return HTTP.Response(500, "generate_query: $(string(e))")
    end

    try
        execute_query(query)
    catch e
        return HTTP.Response(500, "Server error: $(string(e))")
    end
end

function main()
    load_database(RESOURCES)
    serve(port=8888, host="0.0.0.0")
end