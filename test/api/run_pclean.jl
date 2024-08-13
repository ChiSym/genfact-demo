module TestRunPClean

using Test
include("server_fixture.jl")
using .ServerFixture

const _PHYSICIAN_ATTRIBUTES = [:first, :last, :specialty, :degree, :school, :npi]
const _BUSINESS_ATTRIBUTES = [:legal_name, :city, :zip, :addr, :addr2]
@doc """Test that all present row attributes are consistent with the observations.

This takes a row from the joint PClean query results, as well as the queried observations.
"""
function test_present_attributes_consistent(row, observations)
    remap_keys = Dict(:city_name => :city)
    cleaned_observations = Dict(
        get(remap_keys, k, k) => v for (k, v) in observations
    )
    expected_physician = Dict(k => v for (k, v) in cleaned_observations if k in _PHYSICIAN_ATTRIBUTES)
    expected_business = Dict(k => v for (k, v) in cleaned_observations if k in _BUSINESS_ATTRIBUTES)
    if isempty(expected_physician) && isempty(expected_business)
        error("No physician or business attributes assigned!")
    end

    physician = get(row, :physician, Dict{Symbol, String}())
    business = get(row, :business, Dict{Symbol, String}())

    if !isempty(expected_physician)
        for (k, v) in expected_physician
            if k in keys(physician)
                @test physician[k] == v
            end
        end
    end

    if !isempty(expected_business)
        for (k, v) in expected_business
            if k in keys(business)
                @test business[k] == v
            end
        end
    end
end

function is_new_entity(entity)
    :exists in keys(entity) && !entity[:exists]
end

@testset "/run-pclean" begin
    start_test_server()
    @testset "correctly locates the records for Dr. Steven Gilman given detailed information" begin
        observations = Dict(
            :first => "STEVEN",
            :last => "GILMAN",
            :school_name => "ALBANY MEDICAL COLLEGE OF UNION UNIVERSITY",
            :specialty => "DIAGNOSTIC RADIOLOGY",
            :degree => "MD",
            :city_name => "CAMP HILL",
            :addr => "429 N 21ST ST",
            :addr2 => "",
            :zip => "170112202",
            :legal_name => "SPIRIT PHYSICIAN SERVICES INC",
        )
        results = query_pclean(observations)
        @test length(results[:joint]) >= 1
        if !isempty(results[:joint])
            test_present_attributes_consistent(results[:joint][1], observations)
        end
    end

    @testset "correctly locates the records for Dr. Steven Gilman given little information" begin
        observations = Dict(
            :first => "STEVEN",
            :last => "GILMAN",
            :legal_name => "SPIRIT PHYSICIAN SERVICES INC",
        )
        results = query_pclean(observations)
        @test length(results[:joint]) > 0
        if !isempty(results[:joint])
            test_present_attributes_consistent(results[:joint][1], observations)
        end
    end

    @testset "correctly locates records for first GenFact demo example doctors" begin
        observations = Dict(
            :last => "SMITH",
            :city_name => "CAMP HILL",
        )
        results = query_pclean(observations)
        # Ambiguous on all levels -- which Camp Hill Dr. Smith? which business?
        @test length(results[:physicians]) > 1
        @test length(results[:businesses]) > 1
        @test length(results[:joint]) > 1
        if !isempty(results[:joint])
            # top result is usually new entity, so test instead against second result
            test_present_attributes_consistent(results[:joint][2], observations)
        end

        observations = Dict(
            :last => "SMITH",
            :specialty => "PSYCHIATRY",
            :city_name => "CAMP HILL",
        )
        results = query_pclean(observations)
        # Unambiguous what physician, but practice is ambiguous
        existing = [row for row in results[:physicians] if !is_new_entity(row)]
        @test length(existing) == 1
        @test length(results[:businesses]) > 1
        @test length(results[:joint]) > 1
        if !isempty(results[:joint])
            test_present_attributes_consistent(results[:joint][1], observations)
        end

        observations = Dict(
            :first => "LAURA",
            :last => "SMITH",
            :city_name => "SPRINGFIELD",
        )
        results = query_pclean(observations)
        # Strong guess based of who this person is
        @test results[:physicians][1][:count] > 0
        @test length(results[:physicians]) > 0
        @test length(results[:businesses]) > 1
        @test length(results[:joint]) > 1
        if !isempty(results[:joint])
            test_present_attributes_consistent(results[:joint][1], observations)
        end

        observations = Dict(
            :last => "SMITH",
            :specialty => "GASTROENTEROLOGY",
            :city_name => "CAMP HILL",
        )
        results = query_pclean(observations)
        # No/new entity -- no such Dr. Smith but a few businesses in Camp Hill
        @test results[:physician_new_entity] > 0
        @test length(results[:physicians]) == 0
        @test length(results[:businesses]) > 1
        @test length(results[:joint]) > 1
        if !isempty(results[:joint])
            @test :physician ∉ keys(results[:joint][1])
            @test results[:joint][1][:exists] == false
        end
        if !isempty(results[:businesses])
            @test results[:businesses][1][:entity][:city] == observations[:city_name]
        end
    end
    stop_test_server()
end

end
