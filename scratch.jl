# using HTTP
using JSON3
# # curl -X GET http://localhost:8888/run_pclean -H "Content-Type: application/json" -d '{"observations" : {"first": "STEVEN", "last": "GILMAN", "legal_name": "SPIRIT PHYSICIAN SERVICES INC"}}'
# host = "http://localhost:8888"
# body = Dict(
#     "observations" => Dict(
#         "first" => "STEVEN",
#         "last" => "GILMAN",
#         "legal_name" => "SPIRIT PHYSICIAN SERVICES INC"
#     )
# )
# json_data = JSON3.write(body)
# response = HTTP.get("$host/run_pclean", ["Content-Type" => "application/json"], json_data)
# body = JSON3.read(response.body)

using DataFrames
using PrettyTables
using Serialization

body = deserialize("foo.jls")
function group(results)
    physicians = Dict{String, Any}()
    businesses = Dict{String, Any}()
    for ((p_id, b_id), p_entity, b_entity) in results
        # println(p_id)
        # println(b_id)
        # println(entity)
        if !(p_id in keys(physicians))
            physicians[p_id] = []
        end
        push!(physicians[p_id], p_entity)

        if !(b_id in keys(businesses))
            businesses[b_id] = []
        end
        push!(businesses[b_id], b_entity)
    end
    physicians = Dict(Symbol(key)=>first(val) for (key,val) in physicians)
    businesses = Dict(Symbol(key)=>first(val) for (key,val) in businesses)
    physicians, businesses
end



physicians, businesses = group(body[1])
function create_tables(entities, histogram, attributes)
    df = DataFrame([[] for _ in attributes], attributes)
    total = sum(values(histogram))

    freq = Dict(key=>val/total for (key,val) in histogram)
    entities = sort([(key,val) for (key, val) in entities], by=x->freq[x[1]], rev=true)
    highlights = []

    interpolate(x) = round(Int,(255-232)*x+232)
    for (idx,(row_id, entity)) in enumerate(entities)
        push!(df, entity)
        f = (data, i, j) -> (i == idx)
        color = Crayon(background=interpolate(freq[row_id]))
        push!(highlights, Highlighter(f, color))
    end
    df, highlights

end
b_df, b_highlights = create_tables(businesses, body[3], ["legal_name", "addr", "addr2", "city", "zip"])
pretty_table(
    b_df;
    highlighters= Tuple(b_highlights)
)

