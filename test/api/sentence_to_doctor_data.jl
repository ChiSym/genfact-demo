module TestSentenceToDoctorData

using Test

include("server_fixture.jl")
using .ServerFixture

@doc """Extract the top k most likely answers from a structured posterior.

A structured posterior is one where the keys are (potentially modified) inferences,
and the values are objects with a :likelihood key."""
function get_topk_answers(structured_posterior, k)
    function keyfunc(v) v[:likelihood] end
    topk_answers = partialsort(
        collect(values(structured_posterior)),
        1:min(length(structured_posterior), k),
        by=keyfunc,
        rev=true)
    [item[:as_object] for item in topk_answers]
end

@doc """Test that X times out of Y, `expected_answer` ranks among the top k most likely inferences for `sentence`.

Note that k = `answer_must_be_best_of`, X = `expected_queries_successful`, Y = `n_queries`."""
@inline function test_sentence_usually_gets_expected_answer(
    sentence, expected_answer,
    answer_must_be_best_of, n_queries, expected_queries_successful)
    @testset let collected_topk_answers = []
        for _ = 1:n_queries
            response = query_sentence(sentence)
            push!(collected_topk_answers, get_topk_answers(response[:posterior], answer_must_be_best_of))
        end
        @test count(topk_answers -> expected_answer in topk_answers, collected_topk_answers) >= expected_queries_successful
    end
end

@testset "/sentence-to-doctor-data" begin
    start_test_server()
    @testset "correctly parses highly detailed sentences most of the time" begin
        sentence = "John Smith's neurology office (Happy Brain Services LLC) at 512 Example Street Suite 3600 (Camp Hill 17011) is terrible!"
        expected_answer = Dict(
            :first => "JOHN",
            :last => "SMITH",
            :specialty => "NEUROLOGY",
            :legal_name => "HAPPY BRAIN SERVICES LLC",
            :addr => "512 EXAMPLE STREET",
            :city_name => "CAMP HILL",
            :zip => "17011"
        )
        answer_must_be_best_of = 2
        n_queries = 10
        expected_queries_successful = 7
        test_sentence_usually_gets_expected_answer(
            sentence, expected_answer,
            answer_must_be_best_of, n_queries, expected_queries_successful)
    end

    @testset "usually provides reasonable responses when querying using the first GenFact demo examples" begin
        # mostly simple, Dr. Lastname type sentences
        sentence = "Dr. Smith's practice in Camp Hill is great."
        expected_answer = Dict(:last => "SMITH", :city_name => "CAMP HILL")
        answer_must_be_best_of = 2
        n_queries = 10
        expected_queries_successful = 7
        test_sentence_usually_gets_expected_answer(
            sentence, expected_answer,
            answer_must_be_best_of, n_queries, expected_queries_successful)

        sentence = "Dr. Smith's psychiatry practice in Camp Hill is great."
        expected_answer = Dict(:last => "SMITH", :specialty => "PSYCHIATRY", :city_name => "CAMP HILL")
        answer_must_be_best_of = 2
        n_queries = 10
        expected_queries_successful = 8
        test_sentence_usually_gets_expected_answer(
            sentence, expected_answer,
            answer_must_be_best_of, n_queries, expected_queries_successful)

        sentence = "My visit with Dr. Laura Smith in Springfield was great."
        expected_answer = Dict(:first => "LAURA", :last => "SMITH", :city_name => "SPRINGFIELD")
        answer_must_be_best_of = 2
        n_queries = 10
        expected_queries_successful = 6
        test_sentence_usually_gets_expected_answer(
            sentence, expected_answer,
            answer_must_be_best_of, n_queries, expected_queries_successful)

        sentence = "Dr. Smith's gastroenterology practice in Camp Hill is great."
        expected_answer = Dict(:last => "SMITH", :specialty => "GASTROENTEROLOGY", :city_name => "CAMP HILL")
        answer_must_be_best_of = 2
        n_queries = 10
        expected_queries_successful = 8
        test_sentence_usually_gets_expected_answer(
            sentence, expected_answer,
            answer_must_be_best_of, n_queries, expected_queries_successful)
    end
    stop_test_server()
end

end