resolve(table, symb) =
    GenFactDemo.PClean.resolve_dot_expression(GenFactDemo.MODEL, table, symb)

@testset ExtendedTestSet "building query" begin
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
        resolve(:Obs, :(record.p.first)) => "STEVEN",
        resolve(:Obs, :(record.p.last)) => "GILMAN",
        resolve(:Obs, :(record.p.school.name)) => "ALBANY MEDICAL COLLEGE OF UNION UNIVERSITY",
        resolve(:Obs, :(record.p.specialty)) => "DIAGNOSTIC RADIOLOGY",
        resolve(:Obs, :(record.p.degree)) => "MD",
        resolve(:Obs, :(record.a.city.name)) => "CAMP HILL",
        resolve(:Obs, :(record.a.addr)) => "429 N 21ST ST",
        resolve(:Obs, :(record.a.addr2)) => "",
        resolve(:Obs, :(record.a.zip)) => "170112202",
        resolve(:Obs, :(record.a.legal_name)) => "SPIRIT PHYSICIAN SERVICES INC",
    )
    @test query_true == query

    data = Dict(
        "first" => "STEVEN",
        "last" => "GILMAN",
        "legal_name" => "SPIRIT PHYSICIAN SERVICES INC",
    )
    query = GenFactDemo.generate_query(GenFactDemo.MODEL, data)

    query_true = Dict{Int64,Any}(
        resolve(:Obs, :(record.p.first)) => "STEVEN",
        resolve(:Obs, :(record.p.last)) => "GILMAN",
        resolve(:Obs, :(record.a.legal_name)) => "SPIRIT PHYSICIAN SERVICES INC",
    )
    @test query == query_true

    data = Dict("first" => "STEVEN", "birth" => "1/1/1")
    @test_throws GenFactDemo.PCleanException GenFactDemo.generate_query(GenFactDemo.MODEL, data)
end

#####################
# PClean Query Tests
#####################
const PHYSICIAN_RESPONSE_ATTRIBUTES =
    Set(["npi", "first", "last", "degree", "school", "specialty"])
const BUSINESS_RESPONSE_ATTRIBUTES = Set(["addr", "addr2", "zip", "city", "legal_name"])


function verify_entry(
    joint_row,
    expected_physician_attributes,
    expected_business_attributes,
)
    (physician_id, business_id) = joint_row["ids"]
    p_entity = joint_row["physician"]
    b_entity = joint_row["business"]

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
    model,
    query,
    expected_physician_attributes = Dict{String,String}(),
    expected_business_attributes = Dict{String,String}();
    query_attempts = 1,
    expected_min_count = 1,
    expected_max_count = 100,
)
    pclean_results = GenFactDemo.execute_query(query, query_attempts)

    @test Set((
        "physicians", "businesses", "joint",
        "physician_new_entity", "business_new_entity",
        "physician_count", "businesses_count", "joint_count"
    )) == keys(pclean_results)
    physician_histogram = pclean_results["physician_count"]
    business_histogram = pclean_results["businesses_count"]
    results = pclean_results["joint"]
    @test length(results) >= expected_min_count
    @test length(results) <= expected_max_count

    @test sum(values(business_histogram)) == sum(values(physician_histogram))
    verify_entry.(
        results,
        Ref(expected_physician_attributes),
        Ref(expected_business_attributes),
    )
end

@testset ExtendedTestSet "first last address legal_name" begin
    model = GenFactDemo.MODEL

    query = Dict{Int64,Any}(
        resolve(:Obs, :(record.p.first)) => "STEVEN",
        resolve(:Obs, :(record.p.last)) => "GILMAN",
        resolve(:Obs, :(record.a.addr)) => "429 N 21ST ST",
        resolve(:Obs, :(record.a.legal_name)) => "SPIRIT PHYSICIAN SERVICES INC",
    )
    expected_physician_attributes = Dict("npi" => 1124012851, "first" => "STEVEN", "last" => "GILMAN")
    expected_business_attributes = Dict("legal_name" => "SPIRIT PHYSICIAN SERVICES INC")
    verify_pclean_results(model, query, expected_physician_attributes, expected_business_attributes)

    query = Dict{Int64,Any}(
        resolve(:Obs, :(record.p.first)) => "JOHN",
        resolve(:Obs, :(record.p.last)) => "STAGIAS",
        resolve(:Obs, :(record.a.addr)) => "300 GROVE ST",
        resolve(:Obs, :(record.a.legal_name)) => "JOHN G STAGIAS MD PC",
    )
    expected_physician_attributes = Dict("npi" => 1023012424, "first" => "JOHN", "last" => "STAGIAS")
    expected_business_attributes = Dict("legal_name" => "JOHN G STAGIAS MD PC")
    verify_pclean_results(model, query, expected_physician_attributes, expected_business_attributes)

    query = Dict{Int64,Any}(
        resolve(:Obs, :(record.p.first)) => "FERRI",
        resolve(:Obs, :(record.p.last)) => "SMITH",
        resolve(:Obs, :(record.a.addr)) => "751 S BASCOM AVE",
        resolve(:Obs, :(record.a.legal_name)) => "COUNTY OF SANTA CLARA",
    )
    expected_physician_attributes = Dict("npi" => 1235389925, "first" => "FERRI", "last" => "SMITH")
    expected_business_attributes = Dict("legal_name" => "COUNTY OF SANTA CLARA")
    verify_pclean_results(model, query, expected_physician_attributes, expected_business_attributes)
end

@testset ExtendedTestSet "first last legal_name" begin
    model = GenFactDemo.MODEL

    query = Dict{Int64,Any}(
        resolve(:Obs, :(record.p.first)) => "STEVEN",
        resolve(:Obs, :(record.p.last)) => "GILMAN",
        resolve(:Obs, :(record.a.legal_name)) => "SPIRIT PHYSICIAN SERVICES INC",
    )
    expected_physician_attributes = Dict("npi" => 1124012851, "first" => "STEVEN", "last" => "GILMAN")
    expected_business_attributes = Dict("legal_name" => "SPIRIT PHYSICIAN SERVICES INC")
    verify_pclean_results(model, query, expected_physician_attributes, expected_business_attributes, query_attempts=1000, expected_min_count = 8)

    query = Dict{Int64,Any}(
        resolve(:Obs, :(record.p.first)) => "SETH",
        resolve(:Obs, :(record.p.last)) => "RUCHI",
        resolve(:Obs, :(record.a.legal_name)) => "ST. JOHN'S WELL CHILD AND FAMILY CENTER, INC."
    )
    expected_physician_attributes = Dict("npi" => 1861889511, "first" => "STEVEN", "last" => "GILMAN")
    expected_business_attributes = Dict("legal_name" => "ST. JOHN's WELL CHILD AND FAMILY CENTER, INC.")
    verify_pclean_results(model, query, expected_physician_attributes, expected_business_attributes, query_attempts=1000)
end
