# Create a new row trace for the hypothetical row
row_trace = Dict{PClean.VertexID,Any}()
{{preamble}}

# Add it to the trace
obs = trace.tables[:Obs].observations
row_id = gensym()
obs[row_id] = row_trace

samples = []
for _ = 1:{{N}}
    # Perform a Particle Gibbs MCMC move to change our current sample of the row
    PClean.run_smc!(trace, :Obs, row_id, PClean.InferenceConfig(1, 10))
    # Accumulate the sample
    push!(samples, trace.tables[:Obs].rows[row_id][br_idx])
end

countmap(samples)
