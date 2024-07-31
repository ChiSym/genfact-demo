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

function aggregate_joint(samples)
    group = Dict{Tuple{Symbol, Symbol}, Any}()
    total = 0
    for s in samples
        p_id, b_id, p_entity, b_entity, p_exist, b_exist = s
        if p_exist && b_exist
            id = (p_id, b_id)
        elseif p_exist
            id = (p_id, :new_entity)
        elseif b_exist
            id = (:new_entity, b_id)
        else
            id = (:new_entity, :new_entity)
        end

        if !(id in keys(group))
            group[id] =  Dict("id"=> id, "count"=>0)
            if p_exist && b_exist
                group[id]["physician"] = p_entity
                group[id]["business"] = b_entity
            elseif p_exist
                group[id]["physician"] = p_entity
            elseif b_exist
                group[id]["business"] = b_entity
            end
        end

        group[id]["count"] += 1
        total +=1
    end
    println("TOTAL = ", total)
    return group
end