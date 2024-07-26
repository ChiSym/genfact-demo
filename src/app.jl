@get "/" function (request)
    return "Hello :)"
end

const _NOTHING_VALUES = Set(["NULL", "NOTHING", "UNKNOWN", "NONE", "N/A", "NO", "NOT", "I DON'T KNOW", "NOT VALID", "NOT PRESENT"])

@post "/sentence-to-doctor-data" function (request)
    data = json(request)
    sentence = data.sentence

    N_PARTICLES = 15
    MAX_TOKENS = 128
    TEMPERATURE = 1.0

    genparse_params = Dict(
        "prompt" => Mustache.render(json_prompt_template, sentence = sentence), # add sentence to prompt
        "method" => "smc-standard",
        "n_particles" => N_PARTICLES,
        "lark_grammar" => GRAMMAR,
        "proposal_name" => "character",
        "proposal_args" => Dict(),
        "max_tokens" => MAX_TOKENS,
        "temperature" => TEMPERATURE,
    )
    json_data = JSON3.write(genparse_params)

    response =
        HTTP.post(GENPARSE_INFERENCE_URL, ["Content-Type" => "application/json"], json_data)
    response = json(response)

    stringkey_posterior = Dict(String(k) => v for (k, v) in response.posterior)
    @debug "Prompt: $(genparse_params["prompt"])"
    @debug "Posterior: $stringkey_posterior"
    for (inference, _likelihood) in stringkey_posterior
        @debug "Inference: $inference"
    end
    clean_json_posterior =
        aggregate_identical_json(get_aggregate_likelihoods(stringkey_posterior))

    # Map from keys that we generate using Genparse to the keys that the /run-pclean route expects
    # jac: This is temporary until we update the grammar/prompt
    column_names_map =
        Dict("address" => "addr", "address2" => "addr2", "city" => "city_name", "first_name" => "first", "last_name" => "last")

    annotated_sentence_html_posterior = Dict()
    for (inference, likelihood) in clean_json_posterior
        # Post-process the Genparse output to remove empty strings.
        # Llama3 likes to output empty strings for missing values.
        # However, empty strings will cause problems for PClean because it will interpret that
        # to mean "the value of this feature is identically empty" ("this doctor has an empty
        # string for their specialty").
        #
        # We also remove the c2z3 key because the PClean endpoint no longer recognizes this key.
        #
        # We could fix these issues in the grammar, however that is out of scope for the August 1st
        # demo.
        as_object = Dict(
            String(key) => value for (key, value) in JSON3.read(inference)
            if value != "" && uppercase(value) ∉ _NOTHING_VALUES && key != :c2z3
        )
        # jac: Temporary post-processing step to match the keys that the /run-pclean route expects
        # jac: Permanent post-processing step to match the value casing used in the Medicare
        # dataset
        formatted = Dict(
            get(column_names_map, key, key) => uppercase(value) for
            (key, value) in as_object
        )

        annotated_text = """$(make_style_tag(map_attribute_to_color(as_object)))
<p>$(annotate_input_text(sentence, as_object))</p>"""
        annotated_sentence_html_posterior[annotated_text] =
            Dict("as_object" => formatted, "likelihood" => likelihood)
    end

    Dict("posterior" => annotated_sentence_html_posterior)
end

@post "/run-pclean" function (request)
    # trace, query, iterations = try
    data = json(request)
    # println(data)
    if !("observations" in keys(data))
        throw(PCleanException("\"observations\" not specified."))
    end
    iterations = 1000
    table = deserialize("$RESOURCES/database/physician.jls")
    trace = PClean.PCleanTrace(MODEL, table)
    query = generate_query(MODEL, data.observations)
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

function main(host = "0.0.0.0", port = 8888)
    load_database(RESOURCES)
    serve(host = host, port = port)
end
