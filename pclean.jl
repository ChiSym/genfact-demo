using PClean

function load_database()
    return 1
end


function generate_query(data)
    data = Dict(
        "SCHOOL" => "ALBANY MEDICAL COLLEGE OF UNION UNIVERSITY",
        "FIRST" => "STEVEN",
        "LAST" => "GILMAN",
        "C2Z3" => "CA-170",
        "ADDR" => "429 N 21ST ST",
        "ADDR2" => "",
        "LEGAL" => "SPIRIT PHYSICIAN SERVICES INC",
    )
    row_trace = Dict{PClean.VertexID, Any}()
    row_trace[PClean.resolve_dot_expression(trace.model, :Obs, :(p.school.name))] = data["SCHOOL"]
    row_trace[PClean.resolve_dot_expression(trace.model, :Obs, :(p.first))] = data["FIRST"]
    row_trace[PClean.resolve_dot_expression(trace.model, :Obs, :(p.last))] = data["LAST"] 
    row_trace[PClean.resolve_dot_expression(trace.model, :Obs, :(a.city.c2z3))] = data["C2Z3"] 
    row_trace[PClean.resolve_dot_expression(trace.model, :Obs, :(a.addr))] = data["ADDR"] 
    row_trace[PClean.resolve_dot_expression(trace.model, :Obs, :(a.addr2))] = data["ADDR2"] 
    row_trace[PClean.resolve_dot_expression(trace.model, :Obs, :(a.legal_name))] = data["LEGAL"]
    return row_trace
end

function execute_query(query)
end

# include("load_data.jl")

# ##############
# # PHYSICIANS #
# ##############
# const SPECIALITIES = possibilities["Primary specialty"]
# const CREDENTIALS = possibilities["Credential"]
# const SCHOOLS = possibilities["Medical school name"]
# const BUSINESSES = possibilities["Organization legal name"]
# const LASTNAMES = possibilities["Last Name"]

PClean.@model PhysicianModel begin
  @class School begin
    name ~ Unmodeled(); @guaranteed name
  end

  @class Physician begin
    @learned error_prob::ProbParameter{1.0, 1000.0}
    @learned degree_proportions::Dict{String, ProportionsParameter{3.0}}
    @learned specialty_proportions::Dict{String, ProportionsParameter{3.0}}
    npi ~ NumberCodePrior(); @guaranteed npi
    first ~ Unmodeled()
    last ~ Unmodeled()
    school ~ School
    begin
      degree ~ ChooseProportionally(CREDENTIALS, degree_proportions[school.name])
      specialty ~ ChooseProportionally(SPECIALITIES, specialty_proportions[degree])
      degree_obs ~ MaybeSwap(degree, CREDENTIALS, error_prob)
    end
  end

  @class City begin
    c2z3 ~ Unmodeled(); @guaranteed c2z3
    name ~ StringPrior(3, 30, cities[c2z3])
  end

  @class BusinessAddr begin
    addr ~ Unmodeled(); @guaranteed addr
    addr2 ~ Unmodeled(); @guaranteed addr2
    zip ~ StringPrior(3, 10, String[]); @guaranteed zip

    legal_name ~ Unmodeled(); @guaranteed legal_name
    begin
      city ~ City
      city_name ~ AddTypos(city.name, 2)
    end
  end

  @class Obs begin
    p ~ Physician
    a ~ BusinessAddr
  end
end

query = @query PhysicianModel.Obs [
  "NPI" p.npi
  "Primary specialty" p.specialty
  "First Name" p.first
  "Last Name" p.last
  "Medical school name" p.school.name
  "Credential" p.degree p.degree_obs
  "City2Zip3" a.city.c2z3
  "City" a.city.name a.city_name
  "Line 1 Street Address" a.addr
  "Line 2 Street Address" a.addr2
  "Zip Code" a.zip
  "Organization legal name" a.legal_name
];

# observations = [ObservedDataset(query, all_data[1:1000,:])]
# config = PClean.InferenceConfig(5, 3; use_mh_instead_of_pg=true)

# @time begin 
#   trace = initialize_trace(observations, config);
#   run_inference!(trace, config)
# end


# function inference(query::Dict{PClean.VertexID, Any})
#     ROW_ID = 31415926
# end