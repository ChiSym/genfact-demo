using GenFactDemo: global_logger, @get, @post, serve, hello_world, sentence_to_doctor_data, run_pclean

global_logger()

@get "/" hello_world
@post "/sentence-to-doctor-data" sentence_to_doctor_data
@post "/run-pclean" run_pclean

println("Starting server...")
serve(host="0.0.0.0", port=8888)
