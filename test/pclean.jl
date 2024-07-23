@testset ExtendedTestSet "building query" begin
    resolve(table, symb) =
        GenFactDemo.PClean.resolve_dot_expression(GenFactDemo.MODEL, table, symb)

    data = Dict(
        "first" => "STEVEN",
        "last" => "GILMAN",
        "school_name" => "ALBANY MEDICAL COLLEGE OF UNION UNIVERSITY",
        "specialty" => "DIAGNOSTIC RADIOLOGY",
        "degree" => "MD",
        "city_name" => "CAMP HILL",
        "addr" => "429 N 21ST ST",
        "addr2" => "",
        "zip" => "170112202",
        "legal_name" => "SPIRIT PHYSICIAN SERVICES INC",
    )

    query = GenFactDemo.generate_query(GenFactDemo.MODEL, data)
    query_true = Dict{Int64,Any}(
        resolve(:Obs, :(p.first)) => "STEVEN",
        resolve(:Obs, :(p.last)) => "GILMAN",
        resolve(:Obs, :(p.school.name)) => "ALBANY MEDICAL COLLEGE OF UNION UNIVERSITY",
        resolve(:Obs, :(p.specialty)) => "DIAGNOSTIC RADIOLOGY",
        resolve(:Obs, :(p.degree)) => "MD",
        resolve(:Obs, :(a.city.name)) => "CAMP HILL",
        resolve(:Obs, :(a.addr)) => "429 N 21ST ST",
        resolve(:Obs, :(a.addr2)) => "",
        resolve(:Obs, :(a.zip)) => "170112202",
        resolve(:Obs, :(a.legal_name)) => "SPIRIT PHYSICIAN SERVICES INC",
    )
    @test query_true == query

    data = Dict(
        "first" => "STEVEN",
        "last" => "GILMAN",
        "legal_name" => "SPIRIT PHYSICIAN SERVICES INC",
    )
    query = GenFactDemo.generate_query(GenFactDemo.MODEL, data)

    query_true = Dict{Int64,Any}(
        resolve(:Obs, :(p.first)) => "STEVEN",
        resolve(:Obs, :(p.last)) => "GILMAN",
        resolve(:Obs, :(a.legal_name)) => "SPIRIT PHYSICIAN SERVICES INC",
    )
    @test query == query_true

    data = Dict("first" => "STEVEN", "birth" => "1/1/1")
    @test_throws ArgumentError GenFactDemo.generate_query(GenFactDemo.MODEL, data)
end

#####################
# PClean Query Tests
#####################
const PHYSICIAN_RESPONSE_ATTRIBUTES =
    Set(["npi", "first", "last", "degree", "school", "specialty"])
const BUSINESS_RESPONSE_ATTRIBUTES = Set(["addr", "addr2", "zip", "city", "legal_name"])

function verify_entry(
    pclean_triplet,
    expected_physician_attributes,
    expected_business_attributes,
)
    (physician_id, business_id), p_entity, b_entity = pclean_triplet

    @test physician_id != business_id
    @test PHYSICIAN_RESPONSE_ATTRIBUTES == keys(p_entity)
    @test BUSINESS_RESPONSE_ATTRIBUTES == keys(b_entity)

    for (attr, expected_val) in expected_physician_attributes
        @test p_entity[attr] == expected_val
    end

    for (attr, expected_val) in expected_business_attributes
        @test b_entity[attr] == expected_val
    end
end

function verify_pclean_results(
    pclean_results,
    expected_physician_attributes = Dict{String,String}(),
    expected_business_attributes = Dict{String,String}(),
)
    @test Set(("physician_histogram", "results", "business_histogram")) ==
          keys(pclean_results)
    physician_histogram = pclean_results["physician_histogram"]
    business_histogram = pclean_results["business_histogram"]
    results = pclean_results["results"]

    @test sum(values(business_histogram)) == sum(values(physician_histogram))
    verify_entry.(
        results,
        Ref(expected_physician_attributes),
        Ref(expected_business_attributes),
    )
end

@testset ExtendedTestSet "steven gilman" begin
    resolve(table, symb) =
        GenFactDemo.PClean.resolve_dot_expression(GenFactDemo.MODEL, table, symb)
    model = GenFactDemo.MODEL
    query = Dict{Int64,Any}(
        resolve(:Obs, :(p.first)) => "STEVEN",
        resolve(:Obs, :(p.last)) => "GILMAN",
        resolve(:Obs, :(a.addr)) => "429 N 21ST ST",
        resolve(:Obs, :(a.legal_name)) => "SPIRIT PHYSICIAN SERVICES INC",
    )

    trace = GenFactDemo.setup_table(model)
    results = GenFactDemo.execute_query(trace, query)
    verify_pclean_results(
        results,
        Dict("first" => "STEVEN", "last" => "GILMAN"),
        Dict("legal_name" => "SPIRIT PHYSICIAN SERVICES INC"),
    )
end
