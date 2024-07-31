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


@doc """Remove a prefix from a string if it is present."""
function removeprefix(s, p)
    local result
    if startswith(s, p)
        result = SubString(s, length(p) + 1)
    else
        result = s
    end
    return result
end

@doc """Extract code from the code block in a chatty Genparse generation."""
function extract_code_from_response(text::String)::String
    result = strip(removeprefix(text, "<|start_header_id|>assistant<|end_header_id|>"))
    try
        JSON3.read(result)
    catch e
	    throw(NotCodeException("Not formatted properly -- expected chat turn prefix followed by JSON."))
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
        result[inference] += nocode_likelihood / max(n_nocode, 1)
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
    "first" => "extracted_firstname",
    "last" => "extracted_lastname",
    "first_name" => "extracted_firstname",
    "last_name" => "extracted_lastname",
    "specialty" => "extracted_specialty",
    "addr" => "extracted_address",
    "addr2" => "extracted_address2",
    "address" => "extracted_address",
    "address2" => "extracted_address2",
    "c2z3" => "extracted_c2z3",
    "city" => "extracted_city",
    "city_name" => "extracted_city",
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

COLORS = ["teal", "springgreen", "moccasin", "lime", "darkviolet", "cyan", "darkorange", "silver"]

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

const _ATTRIBUTE_TO_COLOR = Dict(
    "first" => "pink",  # was #ff8367
    "first_name" => "pink",
    "last" => "orange",
    "last_name" => "orange",
    "specialty" => "gold",
    "legal_name" => "yellowgreen",
    "addr" => "skyblue",
    "address" => "skyblue",
    "addr2" => "dodgerblue",
    "address2" => "dodgerblue",
    # c2z3 is deprecated and unused, so it can overlap in color with the two
    # attributes it combines/abbreviates (city and zip).
    "c2z3" => "hotpink",
    "city" => "hotpink",
    "city_name" => "hotpink",
    "zip" => "violet",
)

@doc """Given an attribute->value dictionary, map each attribute to a color."""
function map_attribute_to_color(variables)::Dict{String,String}
    result = Dict()
    for (attribute, color) in zip(keys(variables), COLORS)
        result[attribute] = _ATTRIBUTE_TO_COLOR[attribute]
    end

    no_assigned_color = Set([attribute for attribute in keys(variables) if attribute ∉ keys(result)])
    @assert length(no_assigned_color) <= length(COLORS)
    if !isempty(no_assigned_color)
        @debug "Some attributes have no assigned color: $no_assigned_color"
    end
    for (attribute, color) in zip(no_assigned_color, COLORS)
        result[attribute] = color
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
            push!(csslines, ".$class_name { background-color: $(color); }")
        end
    end

    result = """<style>
$(join(csslines, "\n"))
</style>"""
    return result
end

struct LegendEntry
    label::String
    class::String
end

const _GLOSSES = Dict(
    "first" => "Provider first name",
    "last" => "Provider last name",
    "specialty" => "Provider specialty",
    "legal_name" => "Practice legal name",
    "addr" => "Practice address line 1",
    "addr2" => "Practice address line 2",
    "city_name" => "Practice city",
    "zip" => "Practice ZIP code",
)
@doc """Given an attribute, gloss it appropriately for the user."""
function gloss_attribute(attribute)::String
    if attribute in keys(_GLOSSES)
        result = _GLOSSES[attribute]
    else
        result = uppercasefirst(replace(attribute, '_' => ' '))
    end
    return result
end

@doc """Given a list of attributes, generate an appropriate HTML legend box."""
function make_html_legend(legend_entries)::String
    labels = [
        """<label class="$(legend_entry.class)">$(legend_entry.label)</label>"""
        for legend_entry in legend_entries
    ]
    result = """<div class="extraction_legend">
$(join(labels, "\n"))
</div>"""
    return result
end

function get_annotated_sentence_html_posterior(clean_json_posterior, sentence)
    # Map from keys that we generate using Genparse to the keys that the /run-pclean route expects
    # jac: This is temporary until we update the grammar/prompt
    column_names_map =
        Dict("address" => "addr", "address2" => "addr2", "city" => "city_name", "first_name" => "first", "last_name" => "last")

    result = Dict()
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
            if !isnothing(value) && strip(value) != "" && strip(uppercase(value)) ∉ _NOTHING_VALUES && key != :c2z3
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
        result[annotated_text] =
            Dict("as_object" => formatted, "likelihood" => likelihood)
    end
end
