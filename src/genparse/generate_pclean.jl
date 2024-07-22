const FENCE = "```"
const JULIA = "julia"
const NEWLINE = "\n"

# Thanks to https://en.wikibooks.org/wiki/Introducing_Julia/Working_with_text_files
const GRAMMAR = open("./resources/pclean_grammar.lark") do file
    read(file, String)
end
# why specify from_file=false? as in this example: https://docs.juliahub.com/Oxygen/JtS3f/1.5.12/#Mustache-Templating
format_pclean_prompt = mustache_("./resources/templates/pclean_prompt_template.txt", from_file=true) 
format_pclean_code = mustache_("./resources/templates/pclean_template.jl")


@doc """Extract code from the code block in a chatty Genparse generation."""
function extract_code_from_response(text::String)::String
    start = findfirst(FENCE, text).stop + 1

    # Fence may or may not be marked as Julia code
    if startswith(SubString(text, start), JULIA)
        start += length(JULIA)
    end
    # Fence may or may not be marked as Julia code
    @assert startswith(SubString(text, start), NEWLINE)
    start += length(NEWLINE)

    # The code is assumed to lie between the first fence and last fence
    end_ = findlast(FENCE, text).start - 1
    result = strip(SubString(text, start, end_))
    return result 
end

@doc """Sort a posterior distribution so the highest likelihood output comes first.

Breaks ties by preferring the alphabetically earliest inference. This does not explicitly handle Unicode and so it will probably sort in UTF-8 code unit order instead of in collation order.
"""
function sort_posterior(posterior::Dict{String, AbstractFloat})::Dict{String, AbstractFloat}
    return Dict(
        inference => likelihood 
        for (inference, likelihood) in sort(collect(posterior), by=t -> [t[2], t[1]], rev=True)
    )
end

@doc """Convert a raw-text posterior into a code-only posterior.

This extracts the code block from each inference and aggregates the likelihoods from identical code blocks.
"""
function get_aggregate_likelihoods(posterior::Dict{String, AbstractFloat})::Dict{String, AbstractFloat}
    result = Dict()
    for (inference, likelihood) in posterior
        code_only = extract_code_from_response(inference)
        get!(result, code_only, 0.0)
        result[code_only] += likelihood
    end
    return sort_posterior(result)
end


@doc """Normalize a raw JSON object string into a standard form.

This parses the string as an object, sorts by keys, then re-serializes it to eliminate variation in whitespace.
"""
function normalize_json_object(string::String)::String
    result = JSON3.write(Dict(String(k) => v for (k, v) in sort(collect(JSON3.read(string)), by=t -> String(t[1]))))
    return result
end


@doc """Convert a raw-JSON posterior into a normalized-JSON posterior."""
function aggregate_identical_json(posterior::Dict{String, AbstractFloat})::Dict{String, AbstractFloat}
    result = Dict()
    for (inference, likelihood) in posterior
        # Parse, sort keys, and rewrite so that things look proper
        normalized = normalize_json_object(inference)
        get!(result, normalized, 0.0)
        result[normalized] += likelihood
    end
    return sort_posterior(result)
end


resolve_dot_expr_re = r"([a-z_]+_key) = PClean\.resolve_dot_expression\(trace\.model, :Obs, :\(([a-zA-Z_.]+)\)\)"
_CLASS_NAMES::Dict{String, String} = Dict(
    "p.first" => "extracted_firstname",
    "p.last" => "extracted_lastname",
    "p.specialty" => "extracted_specialty",
    "a.addr" => "extracted_address",
    "a.addr2" => "extracted_address2",
    "a.c2z3" => "extracted_c2z3",
    "a.city" => "extracted_city",
    "a.legal_name" => "extracted_legalofficename",
)
@doc """Resolve the given Julia symbol to a CSS class name."""
function get_class_name(symbol)
    return _CLASS_NAMES.get(symbol, "")
end

@doc """Extract a mapping from PClean column symbols to the values assigned."""
function get_variables(inference::String)::Dict{String, String}
    result = Dict()
    # Look for resolve dot expression regexes
    for resolve_dot_expr_match in eachmatch(inference, resolve_dot_expr_re)
        varname = resolve_dot_expr_match.captures[1]
        symbol = resolve_dot_expr_match.captures[2]

        # Find the matching "set value" code
        varname_regex = Regex("\\Q$varname\\E")
        set_value_match = match(
            r"row_trace\[$(varname_regex)\] = \"([a-zA-Z0-9 ]+)\"", 
            inference,
            resolve_dot_expr_match.stop + 1,
        )
        @assert set_value_match
        value_string = set_value_match.captures[1]

        result[symbol] = value_string
    end
end

struct AnnotatedText
    attribute_to_color::Dict{String, String}
    annotated_sentence_html::String
end

COLORS = ["red", "orange", "yellow", "green", "blue", "indigo", "violet"]

@doc """Annotate the given input using HTML span tags."""
function annotate_input_text(input_text::String, variables::Dict{String, String})::String
    # TODO how to escape text as HTML in Julia?
    # result = escape(input_text)
    result = input_text
    # Look for assignments in the generated PClean code,
    # determine the values of those assignments,
    # then highlight the corresponding values in the HTML result.
    for (symbol, value) in variables
        class_name = get_class_name(symbol)
        result = replace(result, value_pattern => s"<span class=\"$class_name\">$value_string</span>")
    end
    return result
end