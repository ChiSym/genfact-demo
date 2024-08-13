module ServerFixture

using GenFactDemo
using JSON3
using HTTP

const _EXTRACT_DOCTOR_DATA_ROUTE = "/sentence-to-doctor-data"
const _QUERY_PCLEAN_ROUTE = "/run-pclean"

const TEST_SERVER_PORT = 27016
const SERVER_START_TIME = 10

function start_test_server()
    GenFactDemo.serve(port=TEST_SERVER_PORT, async=true, show_banner=false)
    sleep(SERVER_START_TIME)
end

function stop_test_server()
    GenFactDemo.terminate()
end

function query_server_json(route, payload)
    if route ∉ [_EXTRACT_DOCTOR_DATA_ROUTE, _QUERY_PCLEAN_ROUTE]
        error("Bad route $route.")
    end

    endpoint = "http://127.0.0.1:$TEST_SERVER_PORT$route"
    println("hitting endpoint $endpoint")
    response =
        HTTP.post(endpoint, ["Content-Type" => "application/json"], JSON3.write(payload))
    JSON3.read(response.body)
end

function query_sentence(sentence)
    payload = Dict(:sentence => sentence)
    data = query_server_json(_EXTRACT_DOCTOR_DATA_ROUTE, payload)
    return data
end

function query_pclean(observations)
    payload = Dict(:observations => observations)
    data = query_server_json(_QUERY_PCLEAN_ROUTE, payload)
    return data
end

export start_test_server, stop_test_server, query_server_json, query_sentence, query_pclean

end
