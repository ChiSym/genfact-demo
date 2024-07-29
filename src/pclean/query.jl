const VALID_ATTRIBUTES = Dict(
    "first" => :(p.first),
    "last" => :(p.last),
    "school_name" => :(p.school.name),
    "specialty" => :(p.specialty),
    "degree" => :(p.degree),
    "city_name" => :(a.city.name),
    "addr" => :(a.addr),
    "addr2" => :(a.addr2),
    "zip" => :(a.zip),
    "legal_name" => :(a.legal_name),
)

"""
    generate_query(model::PClean.PCleanModel, data)

Constructs a row in the observation table using the attributes in data. The keys in data must be a subset of
the keys in VALID_ATTRIBUTES.
"""
function generate_query(model::PClean.PCleanModel, data)
    row_trace = Dict{PClean.VertexID,Any}()
    for (key, value) in data
        key = string(key)
        if !(key in keys(VALID_ATTRIBUTES)) 
            throw(
                PCleanException(
                    "Query key \"$key\" is not a valid attribute. The valid attributes: $(collect(keys(VALID_ATTRIBUTES)))",
                )
            ) 
        end
        attr = VALID_ATTRIBUTES[key]
        row_trace[PClean.resolve_dot_expression(model, :Obs, attr)] = value
    end
    return row_trace
end

"""
    execute_query(trace, row_trace, iterations)

`execute_query` returns a set of physician and practice entities from the PClean database. The returned dictionary contains three 
keys: \"results\", \"physician_histogram\", and \"business_histogram\".
"""
function execute_query(trace, row_trace::PClean.RowTrace, iterations = 100)
    existing_physicians = Set(keys(trace.tables[:Physician].rows))
    existing_businesses = Set(keys(trace.tables[:BusinessAddr].rows))
    existing_observations = Set([
        (
            row[PClean.resolve_dot_expression(trace.model, :Obs, :p)],
            row[PClean.resolve_dot_expression(trace.model, :Obs, :a)],
        ) for (id, row) in trace.tables[:Obs].rows
    ])
    # Wasteful but ok for now.
    row_id = 31415926
    obs = trace.tables[:Obs].observations
    obs[row_id] = row_trace

    physician_samples = Pair{Symbol, Dict{String, Any}}[]
    business_samples = Pair{Symbol, Dict{String, Any}}[]
    joint_samples = Pair{Tuple{Symbol, Symbol}, NTuple{2,Dict{String, Any}}}[]

    for _ = 1:iterations
        try
            PClean.run_smc!(trace, :Obs, row_id, PClean.InferenceConfig(20, 5))
            r_ = copy(trace.tables[:Obs].rows[row_id])
            info = EXTRACTOR(r_)
            p_id = info[1]
            b_id = info[2]
            if p_id in existing_physicians
                push!(physician_samples, p_id => info[3])
            end
            if b_id in existing_businesses
                push!(business_samples, b_id => info[4])
            end
            if (p_id, b_id) in existing_observations
                push!(joint_samples, ((p_id, b_id) => (info[3], info[4])))
            end
        catch e
            # Somehow an element has zero probability. For now ignore.
            if isa(e, DomainError)
                err = e.msg
                @info "run_smc!"  err
            end
        end
    end

    physicians, p_hist = aggregate(physician_samples)
    businesses, b_hist = aggregate(business_samples)
    joint, _ = aggregate(joint_samples)
    joint = [Dict("ids" => dict["id"], "count"=>dict["count"], "physician"=>dict["entity"][1], "business"=>dict["entity"][2]) for dict in joint]
    return Dict(
        "physicians" => physicians,
        "businesses" => businesses,
        "physician_histogram" => p_hist,
        "business_histogram" => b_hist,
        "physician_count" => iterations,
        "businesses_count" => iterations,
        "physician_new_entity" => iterations - length(physician_samples),
        "business_new_entity" => iterations - length(business_samples),
        "results" => joint
    )
end
