function test_extracting_code_works()
    # Test to confirm it works as intended
    text = """<|start_header_id|>assistant<|end_header_id|>
  
    Here is the Julia code to query the PClean table of records about doctors based on the given input sentence:
  
    ```julia
    name_key = PClean.resolve_dot_expression(trace.model, :Obs, :name)
    row_trace[name_key] = "Kay Ryan"
    city_key = PClean.resolve_dot_expression(trace.model, :Obs, :city)
    row_trace[city_key] = "Baltimore"
    ```"""

    expected_code = """name_key = PClean.resolve_dot_expression(trace.model, :Obs, :name)
    row_trace[name_key] = "Kay Ryan"
    city_key = PClean.resolve_dot_expression(trace.model, :Obs, :city)
    row_trace[city_key] = "Baltimore\""""

    result = GeneratePClean.extract_code_from_response(text)
    @test strip(result) == expected_code
end