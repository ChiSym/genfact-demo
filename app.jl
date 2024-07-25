include("src/GenFactDemo.jl")

global_logger()

println("Starting server...")
serve(host="0.0.0.0", port=8888)
