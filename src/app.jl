@get "/" function(request)
    return "Hello :)"
end

@post "/sentence-to-doctor-data" function(request)
    data = json(request)
    sentence = data.sentence

    N_PARTICLES = 15
    MAX_TOKENS = 128
    TEMPERATURE = 1.0

    genparse_params = Dict(
        "prompt" => Mustache.render(json_prompt_template, sentence=sentence), # add sentence to prompt
        "method" => "smc-standard",
        "n_particles" => N_PARTICLES,
        "lark_grammar" => GRAMMAR,
        "proposal_name" => "character",
        "proposal_args" => Dict(),
        "max_tokens" => MAX_TOKENS,
        "temperature" => TEMPERATURE,
    )
    json_data = JSON3.write(genparse_params)

    response = HTTP.post(URL, ["Content-Type" => "application/json"], json_data)
    response = json(response)

    clean_json_posterior = aggregate_identical_json(get_aggregate_likelihoods(response.posterior))

    annotated_sentence_html_posterior = Dict()
    for (inference, likelihood) in clean_json_posterior
        # Post-process the Genparse output to remove empty strings.
        # Llama3 likes to output empty strings for missing values.
        # However, empty strings will cause problems for PClean because it will interpret that
        # to mean "the value of this feature is identically empty" ("this doctor has an empty
        # string for their specialty").
        #
        # We could fix that in the grammar, however that is out of scope for the August 1st
        # demo.
        as_object = Dict(key => value for (key, value) in JSON3.read(inference) if value)

        annotated_text = """$(make_style_tag(map_attribute_to_color(as_object)))
<p>$(annotate_input_text(as_object))</p>"""
        annotated_sentence_html_posterior[annotated_text] = Dict(
            "as_object" => as_object,
            "likelihood" => likelihood,
        )
    end

    Dict("posterior" => annotated_sentence_html_posterior)
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