struct PCleanException <: Exception
    msg::String
end

"""
    load_database(dir)

Loads the PClean schema into memory.
"""
function load_database(dir)
    possibilities = deserialize("$dir/database/possibilities.jls")

    SPECIALITIES = possibilities["Primary specialty"]
    CREDENTIALS = possibilities["Credential"]
    SCHOOLS = possibilities["Medical school name"]
    BUSINESSES = possibilities["Organization legal name"]
    FIRSTNAMES = possibilities["First Name"]
    LASTNAMES = possibilities["Last Name"]
    ADDRS = possibilities["Line 1 Street Address"]
    ADDRS2 = possibilities["Line 2 Street Address"]
    CITIES = possibilities["City"]
    ZIPS = possibilities["Zip Code"]

    PClean.@model PhysicianModel begin
        @class School begin
            @learned school_proportions::ProportionsParameter{3.0}
            name ~ ChooseProportionally(SCHOOLS, school_proportions) 
        end
    
        @class Physician begin
            @learned error_prob::ProbParameter{1.0,1000.0}
            @learned degree_proportions::Dict{String,ProportionsParameter{3.0}}
            @learned specialty_proportions::Dict{String,ProportionsParameter{3.0}}
            @learned first_name_proportions::ProportionsParameter{3.0}
            @learned last_name_proportions::ProportionsParameter{3.0}
    
            npi ~ NumberCodePrior()
            first ~ ChooseProportionally(FIRSTNAMES, first_name_proportions)
            last ~ ChooseProportionally(LASTNAMES, last_name_proportions)
            school ~ School
            begin
                degree ~ ChooseProportionally(CREDENTIALS, degree_proportions[school.name])
                specialty ~ ChooseProportionally(SPECIALITIES, specialty_proportions[degree])
                degree_obs ~ MaybeSwap(degree, CREDENTIALS, error_prob)
            end
        end
    
        @class City begin
            # @learned city_proportions::ProportionsParameter{3.0}
            # name ~ ChooseProportionally(CITIES, city_proportions)
            name ~ StringPrior(3,21, CITIES)
        end
    
        @class BusinessAddr begin
            @learned addr_proportions::ProportionsParameter{3.0}
            @learned addr2_proportions::ProportionsParameter{3.0}
            @learned zip_proportions::ProportionsParameter{3.0}
            addr ~ ChooseProportionally(ADDRS, addr_proportions)
            addr2 ~ ChooseProportionally(ADDRS2, addr2_proportions)
            zip ~ ChooseProportionally(ZIPS, zip_proportions)
            legal_name ~ StringPrior(1,71, BUSINESSES)
    
            begin
                city ~ City
                city_name ~ AddTypos(city.name, 2)
            end
        end
    
        @class EmploymentRecord begin
            p ~ Physician
            a ~ BusinessAddr
        end
    
        @class Obs begin
            record ~ EmploymentRecord
        end
    end;

    return PhysicianModel
end

include("utilities.jl")
include("query.jl")

const MODEL = load_database(RESOURCES)
const EXTRACTOR = attribute_extractors(MODEL)
