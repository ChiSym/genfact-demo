function hello_world(request)
    return "Hello :)"
end

function sentence_to_doctor_data(request)
    data = json(request)
    sentence = data.sentence

    N_PARTICLES = 15
    MAX_TOKENS = 128
    TEMPERATURE = 1.0

    genparse_params = Dict(
        "prompt" => prompt_as_user_chat_msg(
            Mustache.render(json_prompt_template, sentence=sentence)
        ),
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

    annotated_sentence_html_posterior = get_annotated_sentence_html_posterior(
        cleanup_entity_extraction_posterior(clean_json_posterior, sentence),
        sentence,
    )

    Dict("posterior" => annotated_sentence_html_posterior)
end

function run_pclean(request)
    data = json(request)
    observations = data.observations

    ITERATIONS = 2000


    # Construct the PClean query
    query = try
        generate_query(MODEL, observations)
    catch e
        if e isa PCleanException
            @error "generate_query" e.msg
            return HTTP.Response(400, "$(e.msg)")
        end
        rethrow(e)
    end
    @debug "run-pclean" query

    # Inefficient but fine for low workloads.
    results = execute_query(query, ITERATIONS)
    return results
end