# Starting the server is slow (~10s). Extracting entities from a sentence is SLOW, seconds per hit at least.
# Include this file into `runtests.jl` at your own peril.
# I suggest running these tests instead by using julia --project=, tests/api/all_routes.jl.
using Test

include("sentence_to_doctor_data.jl")
include("run_pclean.jl")
