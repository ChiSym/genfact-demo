include("src/GenFactDemo.jl")

println("Starting server...")
serve(host="0.0.0.0", port=8888)
