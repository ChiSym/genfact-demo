@testset "Extracting Code" begin 
    # Test to confirm it works as intended
    text = """<|start_header_id|>assistant<|end_header_id|>

```json
{"last_name": "Ryan", "first_name": "Kay", "city": "Baltimore"}
```"""

    expected_code = """{"last_name": "Ryan", "first_name": "Kay", "city": "Baltimore"}"""

    result = GenFactDemo.extract_code_from_response(text)
    @test strip(result) == expected_code
end

@testset "Normalizing JSON" begin 
    # Test to confirm it works as intended
    raw_json = """   {"last_name": "Smith",  
    "first_name":  "John"   } """
    expected_json = """{"first_name":"John","last_name":"Smith"}"""

    result = GenFactDemo.normalize_json_object(raw_json)
    @test result == expected_json
end