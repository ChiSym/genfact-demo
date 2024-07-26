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

Constructs a row in the observation table using the attributes in `data`. The keys in `data` must be a subset of
the keys in `VALID_ATTRIBUTES`.
"""
function generate_query(model::PClean.PCleanModel, data)
    row_trace = Dict{PClean.VertexID,Any}()
    for (key, value) in data
        key = string(key)
        if !(key in keys(VALID_ATTRIBUTES)) 
            throw(
                PCleanException(
                    "Query key "$key" is not a valid attribute. The valid attributes: $(collect(keys(VALID_ATTRIBUTES)))",
                )
            ) 
        end
        attr = VALID_ATTRIBUTES[key]
        row_trace[PClean.resolve_dot_expression(model, :Obs, attr)] = value
    end
    return row_trace
end

"""
"""
function execute_query(trace, row_trace::PClean.RowTrace, iterations = 100)
    existing_physicians = keys(trace.tables[:Physician].rows)
    existing_businesses = keys(trace.tables[:BusinessAddr].rows)
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

    samples = []
    for _ = 1:iterations
        PClean.run_smc!(trace, :Obs, row_id, PClean.InferenceConfig(20, 5))
        r_ = copy(trace.tables[:Obs].rows[row_id])
        info = EXTRACTOR(r_)
        if info[1] in existing_observations
            push!(samples, info)
        end
    end

    data, p_hist, a_hist = build_response(samples)
    return Dict(
        "results" => data,
        "physician_histogram" => p_hist,
        "business_histogram" => a_hist,
    )
end
