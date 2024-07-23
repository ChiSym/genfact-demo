using DataFrames
using PrettyTables
using Serialization

function group(results)
    physicians = Dict{String,Any}()
    businesses = Dict{String,Any}()
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
    physicians = Dict(Symbol(key) => first(val) for (key, val) in physicians)
    businesses = Dict(Symbol(key) => first(val) for (key, val) in businesses)
    physicians, businesses
end

function create_tables(entities, histogram, attributes)
    df = DataFrame([[] for _ in attributes], attributes)
    total = sum(values(histogram))

    freq = Dict(key => val / total for (key, val) in histogram)
    entities =
        sort([(key, val) for (key, val) in entities], by = x -> freq[x[1]], rev = true)
    highlights = []

    interpolate(x) = round(Int, (255 - 232) * x + 232)
    for (idx, (row_id, entity)) in enumerate(entities)
        push!(df, entity)
        f = (data, i, j) -> (i == idx)
        color = Crayon(background = interpolate(freq[row_id]))
        push!(highlights, Highlighter(f, color))
    end
    freq = sort(collect(values(freq)))
    df, highlights, freq

end
