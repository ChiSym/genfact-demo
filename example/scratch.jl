using HTTP
using JSON3


# curl "${host:?}"/sentence-to-doctor-data --request POST --header "Content-Type: application/json" --data '{"sentence": "John Smith'\''s neurology office (Happy Brain Services LLC) at 512 Example Street Suite 3600 (CA-170) is terrible!"}'

host = "http://localhost:8888"
function endpoint1(sentence)
    body = Dict(
        "sentence" => sentence
    )
    body = JSON3.write(body)
    
    url = "$host/sentence-to-doctor-data"
    response = HTTP.post(url, ["Content-Type"=>"application/json"], body)
    response = JSON3.read(response.body)
end

function postprocess(response)
    result = response[:posterior]
    k = rand(keys(response[:posterior]))
    pclean_request = result[k][:as_object]
    # display(pclean_request)
    pclean_request = Dict(
        "observations" => Dict(
            "first"=> pclean_request["first_name"],
            "last" => pclean_request["last_name"],
            # "specialty" => pclean_request["specialty"],
            # "addr" => pclean_request["addr"],
            "legal_name" => pclean_request["legal_name"]
        )
    )
end

function endpoint2(request)
    pclean_request = JSON3.write(request)
    url = "$host/run_pclean"
    response = HTTP.get(url, ["Content-Type"=>"application/json"], pclean_request)
    JSON3.read(response.body)
end

sentence_1 = "Steven Gilman's diagnostic radiology office (Spirit Physician Services Inc) at is terrible!" 
# sentence_2 = "Steven Gilman's diagnostic radiology office (Spirit Physician Services Inc) at 429 N 21ST St (CA-170) is terrible!" 

# 429 N 21ST ST
response1 = endpoint1(sentence_1)
pclean_request = postprocess(response1)
response2 = endpoint2(pclean_request)

include("viz.jl")

physicians, businesses = group(response2["results"])
b_df, b_highlights, b_freq = create_tables(businesses, response2["business_histogram"], ["legal_name", "addr", "addr2", "city", "zip"])
pretty_table(
    b_df;
    highlighters= Tuple(b_highlights)
)