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

@testset "Annotating input HTML" begin 
    sentence = "John Smith's neurology office (Happy Brain Services LLC) at 512 Example Street Suite 3600 (CA-170) is terrible!"
    variables = Dict(
        "first_name" => "John",
        "last_name" => "Smith",
        "specialty" => "neurology",
        "legal_name" => "Happy Brain Services LLC",
        "address" => "512 Example Street",
        "address2" => "Suite 3600",
        "c2z3" => "CA-170",
    )
    expected_annotation = """<span class="extracted_firstname">John</span> <span class="extracted_lastname">Smith</span>&#39;s <span class="extracted_specialty">neurology</span> office (<span class="extracted_legalofficename">Happy Brain Services LLC</span>) at <span class="extracted_address">512 Example Street</span> <span class="extracted_address2">Suite 3600</span> (<span class="extracted_c2z3">CA-170</span>) is terrible!"""

    result = GenFactDemo.annotate_input_text(sentence, variables)
    @test result == expected_annotation
end

@testset "Assigning Attribute Colors" begin 
    variables = Dict(
        "first_name" => "John",
        "last_name" => "Smith",
        "specialty" => "neurology",
        "legal_name" => "Happy Brain Services LLC",
        "address" => "512 Example Street",
        "address2" => "Suite 3600",
        "c2z3" => "CA-170",
    )
    expected_attributes = keys(variables)

    result = GenFactDemo.map_attribute_to_color(variables)

    @test keys(result) == expected_attributes
end