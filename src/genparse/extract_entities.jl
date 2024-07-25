const FENCE = "```"
const JSON = "json"
const NEWLINE = "\n"

# Thanks to https://en.wikibooks.org/wiki/Introducing_Julia/Working_with_text_files
const GRAMMAR = open("$(@__DIR__)/../../resources/json_grammar.lark") do file
    read(file, String)
end
# why specify from_file=false? as in this example: https://docs.juliahub.com/Oxygen/JtS3f/1.5.12/#Mustache-Templating
# maybe because it actually calls a method that may be deprecated in the future:
# https://docs.juliahub.com/General/Mustache/stable/#Mustache.render_from_file-Tuple{Any,%20Any}
json_prompt_template =
    Mustache.load("$(@__DIR__)/../../resources/templates/json_prompt_template.txt")

struct NotCodeException <: Exception
    msg::String
end


@doc """Extract code from the code block in a chatty Genparse generation."""
function extract_code_from_response(text::String)::String
    first_fence = findfirst(FENCE, text)
    last_fence = findlast(FENCE, text)
    if !isnothing(first_fence) && !(isnothing(last_fence)) && first_fence.stop < last_fence.start
        start::Int64 = first_fence.stop + 1

        # Fence may or may not be marked as JSON
        if startswith(SubString(text, start), JSON)
            start += length(JSON)
        end
        if !startswith(SubString(text, start), NEWLINE)
            throw(NotCodeException("First code fence is not followed by [\"json\"] \"\\n\"."))
        end
        start += length(NEWLINE)

        # The code is assumed to lie between the first fence and last fence
        end_::Int64 = last_fence.start - 1
        result::String = strip(SubString(text, start, end_))
    else
        throw(NotCodeException("Text does not contain a complete code block."))
    end
    return result
end

@doc """Sort a posterior distribution so the highest likelihood output comes first.

Breaks ties by preferring the alphabetically earliest inference. This does not explicitly handle Unicode and so it will probably sort in UTF-8 code unit order instead of in collation order.

The posterior should be a dict-like object mapping strings-like objects to float-likes.
This returns a value in the same format.
"""
function sort_posterior(posterior)
    return Dict(
        inference => likelihood for (inference, likelihood) in
        sort(collect(posterior), by = t -> [t[2], t[1]], rev = true)
    )
end

@doc """Convert a raw-text posterior into a code-only posterior.

This extracts the code block from each inference and aggregates the likelihoods from identical code blocks.

The posterior should be a dict-like object mapping strings-like objects to float-likes.
This returns a value in the same format.
"""
function get_aggregate_likelihoods(posterior)
    result = Dict()
    n_nocode = 0
    nocode_likelihood = 0.0
    for (inference, likelihood) in posterior
        local code_only
        try
            code_only = extract_code_from_response(inference)
        catch e
            if isa(e, NotCodeException)
                n_nocode += 1
                nocode_likelihood += likelihood
            else
                rethrow()
            end
        else
            get!(result, code_only, 0.0)
            result[code_only] += likelihood
        end
    end
    for inference in keys(result)
        result[inference] += nocode_likelihood / n_nocode
    end
    @assert !isempty(result)
    return sort_posterior(result)
end


@doc """Normalize a raw JSON object string into a standard form.

This parses the string as an object, sorts by keys, then re-serializes it to eliminate variation in whitespace.
"""
function normalize_json_object(string::String)::String
    result = JSON3.write(
        Dict(
            String(k) => v for
            (k, v) in sort(collect(JSON3.read(string)), by = t -> String(t[1]))
        ),
    )
    return result
end


@doc """Convert a raw-JSON posterior into a normalized-JSON posterior.

The posterior should be a dict-like object mapping strings-like objects (unparsed JSON) to float-likes.
This returns a value in the same format.
"""
function aggregate_identical_json(posterior)
    result = Dict()
    for (inference, likelihood) in posterior
        # Parse, sort keys, and rewrite so that things look proper
        normalized = normalize_json_object(inference)
        get!(result, normalized, 0.0)
        result[normalized] += likelihood
    end
    return sort_posterior(result)
end


resolve_dot_expr_re =
    r"([a-z_]+_key) = PClean\.resolve_dot_expression\(trace\.model, :Obs, :\(([a-zA-Z_.]+)\)\)"
_CLASS_NAMES::Dict{String,String} = Dict(
    "first_name" => "extracted_firstname",
    "last_name" => "extracted_lastname",
    "specialty" => "extracted_specialty",
    "address" => "extracted_address",
    "address2" => "extracted_address2",
    "c2z3" => "extracted_c2z3",
    "city" => "extracted_city",
    "zip" => "extracted_zip",
    "legal_name" => "extracted_legalofficename",
)
@doc """Resolve the given Julia symbol to a CSS class name."""
function get_class_name(symbol)
    return get(_CLASS_NAMES, symbol, "")
end

@doc """Extract a mapping from PClean column symbols to the values assigned."""
function get_variables(inference::String)::Dict{String,String}
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
    attribute_to_color::Dict{String,String}
    annotated_sentence_html::String
end

COLORS = ["red", "orange", "gold", "green", "blue", "indigo", "violet"]

@doc """Annotate the given input using HTML span tags."""
function annotate_input_text(
    input_text::String,
    variables::AbstractDict{String,String},
)::String
    # jac: Hacky way to escape input text as HTML
    result = Mustache.render(mt"{{:s}}", s = input_text)

    for (symbol, value) in variables
        class_name = get_class_name(symbol)
        if class_name != ""
            html_escaped_value = Mustache.render(mt"{{:s}}", s = value)
            value_pattern = Regex("\\Q$html_escaped_value\\E")
            result = replace(
                result,
                value_pattern => "<span class=\"$class_name\">$html_escaped_value</span>",
            )
        end
    end

    return result
end

@doc """Given an attribute->value dictionary, map each attribute to a color."""
function map_attribute_to_color(variables)::Dict{String,String}
    @assert length(variables) <= length(COLORS)
    result = Dict()
    for ((symbol, value), color) in zip(variables, COLORS)
        result[symbol] = color
    end
    return result
end

@doc """Given an attribute->color dictionary, generate an appropriate HTML style tag string.

This assumes that the attributes are among the known entity attributes such that
we know what class name to assign each attribute."""
function make_style_tag(attribute_to_color)::String
    csslines::Vector{String} = []
    for (attribute, color) in attribute_to_color
        class_name = get_class_name(attribute)
        if class_name != ""
            push!(csslines, ".$class_name { color: $(color); }")
        end
    end

    result = """<style>
$(join(csslines, "\n"))
</style>"""
    return result
end
