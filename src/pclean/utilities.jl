function setup_table(model)
    table = deserialize("$RESOURCES/database/physician.jls")
    return PClean.PCleanTrace(model, table)
end


function attribute_extractors(model::PClean.PCleanModel)
    physician_attributes = Dict(
        "npi" => PClean.resolve_dot_expression(model, :Obs, :(record.p.npi)),
        "first" => PClean.resolve_dot_expression(model, :Obs, :(record.p.first)),
        "last" => PClean.resolve_dot_expression(model, :Obs, :(record.p.last)),
        "degree" => PClean.resolve_dot_expression(model, :Obs, :(record.p.degree)),
        "specialty" => PClean.resolve_dot_expression(model, :Obs, :(record.p.specialty)),
        "school" => PClean.resolve_dot_expression(model, :Obs, :(record.p.school.name)),
    )

    business_attributes = Dict(
        "legal_name" => PClean.resolve_dot_expression(model, :Obs, :(record.a.legal_name)),
        "addr" => PClean.resolve_dot_expression(model, :Obs, :(record.a.addr)),
        "addr2" => PClean.resolve_dot_expression(model, :Obs, :(record.a.addr2)),
        "zip" => PClean.resolve_dot_expression(model, :Obs, :(record.a.zip)),
        "city" => PClean.resolve_dot_expression(model, :Obs, :(record.a.city.name)),
    )

    function attributes(row)
        physician_attr =
            Dict(attribute => row[id] for (attribute, id) in physician_attributes)
        business_attr =
            Dict(attribute => row[id] for (attribute, id) in business_attributes)
        physician_id = row[PClean.resolve_dot_expression(model, :Obs, :(record.p))]
        business_id = row[PClean.resolve_dot_expression(model, :Obs, :(record.a))]
        return physician_id, business_id, physician_attr, business_attr
    end

    return attributes
end

function histogram(entities::Vector{<:Pair{T}}) where T
    frequencies = Dict{T,Int}()
    for result in entities
        id = first(result)
        if !(id in keys(frequencies))
            frequencies[id] = 0
        end
        frequencies[id] += 1
    end
    frequencies
end

function aggregate(samples)
    freq = histogram(samples)
    entities = unique(result -> first(result), samples)
    data = [Dict("id"=> first(pair), "entity"=>last(pair), "count"=>freq[first(pair)]) for pair in entities]
    return data, freq
end
