@get "/" function (request)
    return "Hello :)"
end

const _NOTHING_VALUES = Set([
    "REDACTED", "NULL", "NOTHING", "UNKNOWN", "NONE", "N/A", "NO", "NOT", "I DON'T KNOW",
    "NOT VALID", "NOT PRESENT", "DR."
])

@post "/sentence-to-doctor-data" function (request)
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
        as_object = Dict{String, String}(
            String(key) => value for (key, value) in JSON3.read(inference)
            if value != "" && strip(uppercase(value)) ∉ _NOTHING_VALUES && key != :c2z3
                # Llama 3.1 sometimes confabulates values not present in the input sentence.
                # We don't want to query on those and we don't want to display them in the legend.
                #
                # Hack: If the value's not a substring of the sentence, we don't include it in the
                # object.
                #
                # Substring inclusion is not exactly the right thing, because it may discount ways
                # the information may show up in the sentence indirectly. For example, "I love Dr.
                # John Smith's office, I can always see the Golden Gate Bridge from his lobby"
                # implies he's probably practicing in San Francisco or else a very nearby
                # suburb/town. But it's good enough for now.
                #
                # Further Hack: If we don't match a substring of the sentence, we try removing
                # hyphens from the sentence so that ZIPs are correctly recognized as substrings.
                # We need to do this because the ZIP codes, as parsed by Llama, shouldn't include
                # the hyphen.
                && (!isnothing(findfirst(value, sentence))
                    || !isnothing(findfirst(value, replace(sentence, "-" => ""))))
        )
        # jac: Temporary post-processing step to match the keys that the /run-pclean route expects
        # jac: Permanent post-processing step to match the value casing used in the Medicare
        # dataset
        formatted = Dict(
            get(column_names_map, key, key) => uppercase(value) for
            (key, value) in as_object
        )

        colors = map_attribute_to_color(as_object)
        legend_entries = [
            LegendEntry(gloss_attribute(attribute), get_class_name(attribute))
            for attribute in keys(as_object)
        ]
        annotated_text = """$(make_style_tag(colors))
<p>$(annotate_input_text(sentence, as_object))</p>
$(make_html_legend(legend_entries))"""
        annotated_sentence_html_posterior[annotated_text] =
            Dict("as_object" => formatted, "likelihood" => likelihood)
    end

    Dict("posterior" => annotated_sentence_html_posterior)
end

@post "/run-pclean" function (request)
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

function main(host = "0.0.0.0", port = 8888)
    load_database(RESOURCES)
    serve(host = host, port = port)
end
