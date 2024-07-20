function load_database(dir)
    possibilities = deserialize("$dir/database/possibilities.jls")
    SPECIALITIES = possibilities["Primary specialty"]
    CREDENTIALS = possibilities["Credential"]
    # SCHOOLS = possibilities["Medical school name"]
    # BUSINESSES = possibilities["Organization legal name"]
    # LASTNAMES = possibilities["Last Name"]

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

    table = deserialize("$dir/database/physician.jls")
    trace = PClean.PCleanTrace(PhysicianModel, table)
    return PhysicianModel, trace
end
