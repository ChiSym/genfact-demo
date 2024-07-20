function generate_query(data)
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
  row_id = 31415926
  obs = TRACE.tables[:Obs].observations
  obs[row_id] = row_trace

  for _ in 1:10
    PClean.run_smc!(TRACE, :Obs, row_id, PClean.InferenceConfig(10,10))
  end

  return 0
end
