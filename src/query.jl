function generate_query(data)
    data = Dict(
        "SCHOOL" => "ALBANY MEDICAL COLLEGE OF UNION UNIVERSITY",
        "FIRST" => "STEVEN",
        "LAST" => "GILMAN",
        "C2Z3" => "CA-170",
        "ADDR" => "429 N 21ST ST",
        "ADDR2" => "",
        "LEGAL" => "SPIRIT PHYSICIAN SERVICES INC",
    )
    row_trace = Dict{PClean.VertexID, Any}()
    row_trace[PClean.resolve_dot_expression(TRACE.model, :Obs, :(p.school.name))] = data["SCHOOL"]
    row_trace[PClean.resolve_dot_expression(TRACE.model, :Obs, :(p.first))] = data["FIRST"]
    row_trace[PClean.resolve_dot_expression(TRACE.model, :Obs, :(p.last))] = data["LAST"] 
    row_trace[PClean.resolve_dot_expression(TRACE.model, :Obs, :(a.city.c2z3))] = data["C2Z3"] 
    row_trace[PClean.resolve_dot_expression(TRACE.model, :Obs, :(a.addr))] = data["ADDR"] 
    row_trace[PClean.resolve_dot_expression(TRACE.model, :Obs, :(a.addr2))] = data["ADDR2"] 
    row_trace[PClean.resolve_dot_expression(TRACE.model, :Obs, :(a.legal_name))] = data["LEGAL"]
    return row_trace
end

function execute_query(row_trace::PClean.RowTrace)
  ROW_ID = 31415926
  # println(typeof(TRACE))
  # obs = TRACE.tables[:Obs].observations
  # obs[ROW_ID] = row_trace

  # specialty_samples = String[]
  # last_name_samples = String[]
  # physician_ids = Symbol[]

  # for _ in 1:10
  #   PClean.run_smc!(trace, :Obs, row_id, PClean.InferenceConfig(10,10))
  # end

  return 0
end
