using JuMP
using PowerModels
using Gurobi
using DataFrames
using Plots
using Plots.PlotMeasures
using SparseArrays
using CSV
using StatsBase

## reading data using PowerModels 
NetworkData = PowerModels.parse_file("Systeminfo.m") 
ref = PowerModels.build_ref(NetworkData)[:it][:pm][:nw][0]  # extract useful data
baseMVA = NetworkData["baseMVA"]

## read 8760 Hourly data
HourlyData = DataFrame(CSV.File("8760data.csv"))
HourlyLoad = HourlyData[!, :Load]
REhourlyCF = HourlyData[!, :REHourlyCF]
REyearlyCF = mean(REhourlyCF)


## Define generator type 
Ncoal = 6;
Ncc = 3;
Nct = 6;
Noil = 1;
NRE = 1;
RegRE = 0.06; #regulation capacity of renewable
gentype = vcat(repeat(["Coal"],Ncoal),repeat(["CC"],Ncc),repeat(["CT"],Nct),repeat(["Oil"],Noil),repeat(["RE"],NRE))
#create "gentype" in ref
for i in 1:length(ref[:gen])
    ref[:gen][i]["type"] = gentype[i]
end
#assign parameters to each type of generators
for i in 1:length(ref[:gen])
    if ref[:gen][i]["type"] == "CC"
        ref[:gen][i]["fprice"] = 4 # fuel price, $/mmbtu
        ref[:gen][i]["Rcost"] = 6 #reserve cost, $/MW
        ref[:gen][i]["Rmax"] = 0.05* ref[:gen][i]["pmax"] #reserve capacity, MW
        ref[:gen][i]["VOM"] = 2 # variable O&M cost, $/MWh
        ref[:gen][i]["ER"] = 0.053  #emission, metric tons/mmbtu
    elseif ref[:gen][i]["type"] == "CT"
        ref[:gen][i]["fprice"] = 4
        ref[:gen][i]["Rcost"] = 4
        ref[:gen][i]["Rmax"] = 0.08 * ref[:gen][i]["pmax"]
        ref[:gen][i]["VOM"] = 1
        ref[:gen][i]["ER"] = 0.053 
    elseif ref[:gen][i]["type"] == "Coal"
        ref[:gen][i]["fprice"] = 3
        ref[:gen][i]["Rcost"] = 10
        ref[:gen][i]["Rmax"] = 0.02 * ref[:gen][i]["pmax"]
        ref[:gen][i]["VOM"] = 4
        ref[:gen][i]["ER"] = 0.095
    elseif ref[:gen][i]["type"] == "RE"
        ref[:gen][i]["fprice"] = 0
        ref[:gen][i]["Rcost"] = 1
        ref[:gen][i]["Rmax"] = RegRE * ref[:gen][i]["pmax"]
        ref[:gen][i]["VOM"] = 0
        ref[:gen][i]["ER"] = 0 
    elseif ref[:gen][i]["type"] == "Oil"
        ref[:gen][i]["fprice"] = 7
        ref[:gen][i]["Rcost"] = 4
        ref[:gen][i]["Rmax"] = 0.08 * ref[:gen][i]["pmax"]
        ref[:gen][i]["VOM"] = 1
        ref[:gen][i]["ER"] = 0.073 
    end
end

FOM = [250000.0,275000.0,350000.0,350000.0,480000.0,630000.0,36000.0,50000.0,112500.0,28000.0,28000.0,28000.0,32000.0,32000.0,40000.0, 0, 0]

## add storage into ref structure
ref[:bus_ES] = Dict{Int64, Any}()
for i = keys(ref[:bus])
    ref[:bus_ES][i] = []
end
ref[:bus_ES][7] = 1
ref[:load_ES] = Dict{Int64, Any}()
ref[:load_ES][1] = 1
Rmax_ES = 0 #maximum reserve capacity of es
Rcost_ES = 1 #reserve cost of es
ESrate = 0.05 #es increasing rate

## carbon tax (adjust carbon tax here)
Ctax = 10 

## forced coal retirement (adjust forced coal retirement here)
forceunit = 0
forceyear = 0

## system reserve requirement (will be changed later when solve)
Rreq = 20/baseMVA

##
Nbus = length(keys(ref[:bus]))
Ngen = length(keys(ref[:gen]))
Nline = length(keys(ref[:branch]))

## build the optimization model using JuMP
Hourspersolve = 24 #Solve for one day each time
PSdecarbonization = Model(Gurobi.Optimizer)
@variable(PSdecarbonization, Pg[i in keys(ref[:gen]),t=1:Hourspersolve] >= 0)
@variable(PSdecarbonization, Rg[i in keys(ref[:gen]),t=1:Hourspersolve] >= 0)
@variable(PSdecarbonization, Rg_ES[t=1:Hourspersolve] >= 0)
@variable(PSdecarbonization, UC[i in keys(ref[:gen]),t=1:Hourspersolve], Bin)
@variable(PSdecarbonization, loadloss[t=1:Hourspersolve] >= 0) #new variable in the 8760-hour model
@variable(PSdecarbonization, reserveloss[t=1:Hourspersolve] >= 0) #new variable in the 8760-hour model

@constraint(PSdecarbonization, pgupper[i in keys(ref[:gen]),t=1:Hourspersolve], Pg[i,t] + Rg[i,t] <= UC[i,t] * ref[:gen][i]["pmax"])
@constraint(PSdecarbonization, pglower[i in keys(ref[:gen]),t=1:Hourspersolve], Pg[i,t] - Rg[i,t] >= UC[i,t] * ref[:gen][i]["pmin"])
@constraint(PSdecarbonization, rgupper[i in keys(ref[:gen]),t=1:Hourspersolve], Rg[i,t] <= ref[:gen][i]["Rmax"])
@constraint(PSdecarbonization, rgupper_ES[t=1:Hourspersolve], Rg_ES[t] <= Rmax_ES)
@constraint(PSdecarbonization, rglower[t=1:Hourspersolve], Rg_ES[t] + reserveloss[t] + sum(Rg[i,t] for i in keys(ref[:gen])) >= Rreq)
@constraint(PSdecarbonization, pgnodal[t=1:Hourspersolve], sum(Pg[a,t] for a in 1:Ngen) + loadloss[t] - sum(ref[:load][d]["pd"] for d in 1:3) - 0.038*Rg_ES[t] == 0)
#objective
@objective(PSdecarbonization, Min, sum(Rg_ES[t]*Rcost_ES*baseMVA + (reserveloss[t]+loadloss[t])*1000000 + sum((gen["fprice"] + gen["ER"]*Ctax)*(gen["cost"][1]*(Pg[i,t])^2 +gen["cost"][2]*Pg[i,t] + UC[i,t]*gen["cost"][3]) + gen["VOM"]*Pg[i,t]*baseMVA + Rg[i,t]*baseMVA*gen["Rcost"] for (i,gen) in ref[:gen]) for t in 1:Hourspersolve))

## fixed model
Fixedmodel = Model(Gurobi.Optimizer)
@variable(Fixedmodel, Pg_f[i in keys(ref[:gen]),t=1:Hourspersolve] >= 0)
@variable(Fixedmodel, Rg_f[i in keys(ref[:gen]),t=1:Hourspersolve] >= 0)
@variable(Fixedmodel, Rg_ES_f[t=1:Hourspersolve] >= 0)
@variable(Fixedmodel, 0 <= UC_f[i in keys(ref[:gen]),t=1:Hourspersolve] <= 1)
@variable(Fixedmodel, loadloss_f[t=1:Hourspersolve] >= 0)
@variable(Fixedmodel, reserveloss_f[t=1:Hourspersolve] >= 0)

@constraint(Fixedmodel, pgupper_f[i in keys(ref[:gen]),t=1:Hourspersolve], Pg_f[i,t] + Rg_f[i,t] <= UC_f[i,t] * ref[:gen][i]["pmax"])
@constraint(Fixedmodel, pglower_f[i in keys(ref[:gen]),t=1:Hourspersolve], Pg_f[i,t] - Rg_f[i,t] >= UC_f[i,t] * ref[:gen][i]["pmin"])
@constraint(Fixedmodel, rgupper_f[i in keys(ref[:gen]),t=1:Hourspersolve], Rg_f[i,t] <= ref[:gen][i]["Rmax"])
@constraint(Fixedmodel, rgupper_ES_f[t=1:Hourspersolve], Rg_ES_f[t] <= Rmax_ES)
@constraint(Fixedmodel, rglower_f[t=1:Hourspersolve], Rg_ES_f[t] + reserveloss_f[t] + sum(Rg_f[i,t] for i in keys(ref[:gen])) >= Rreq)
@constraint(Fixedmodel, pgnodal_f[t=1:Hourspersolve], sum(Pg_f[a,t] for a in 1:Ngen) + loadloss_f[t] - sum(ref[:load][d]["pd"] for d in 1:3) - 0.038*Rg_ES_f[t] == 0)

@objective(Fixedmodel, Min, sum(Rg_ES_f[t]*Rcost_ES*100 + (reserveloss_f[t]+loadloss_f[t])*1000000 + sum((gen["fprice"] + gen["ER"]*Ctax)*(gen["cost"][1]*(Pg_f[i,t])^2 +gen["cost"][2]*Pg_f[i,t] + UC_f[i,t]*gen["cost"][3]) + gen["VOM"]*Pg_f[i,t]*100 + Rg_f[i,t]*100*gen["Rcost"] for (i,gen) in ref[:gen]) for t in 1:Hourspersolve))
@constraint(Fixedmodel, unitc_f[i in keys(ref[:gen]),t=1:Hourspersolve], UC_f[i,t] == 1) #fix all integer variable; right-hand side value would be changed later

## Solve the problem
year = 11
Hours = 8760
Totalsolve = Int(Hours/Hourspersolve)

#results of variables
result_obj = zeros(1,year*Totalsolve)
result_gen = zeros(Ngen, year*Hours)
result_UC = zeros(Ngen, year*Hours)
result_reserve = zeros(Ngen, year*Hours)
result_bus = zeros(Nbus, year*Hours)
result_line = zeros(Nline*2, year*Hours)
result_ES = zeros(1, year*Hours)
result_dual = zeros(Nbus, year*Hours)
result_Rprice = zeros(1, year*Hours)
result_loadloss = zeros(1, year*Hours)
result_reserveloss = zeros(1, year*Hours)

#results of further calculation
result_yearobj = zeros(year)
result_gencost = zeros(Ngen, year*Hours)
result_genCTcost = zeros(Ngen, year*Hours)
result_reservecost = zeros(Ngen, year*Hours)
result_genrevenue = zeros(Ngen, year*Hours)
result_reserverevenue = zeros(Ngen, year*Hours)
result_profit = zeros(Ngen, year*Hours)
result_yearprofit = zeros(Ngen, year)
result_netprofit = zeros(Ngen, year)
result_genmargin = zeros(Ngen, year*Hours)
result_yeargen = zeros(Ngen, year)
result_yearreserve = zeros(Ngen, year)
result_yearES = zeros(1, year)
result_yearCTcost = zeros(Ngen, year)
result_genemission = zeros(Ngen, year*Hours) #generator hourly emissions
result_yeargen_emission = zeros(Ngen, year) #generator yearly emissions
result_yeargen_emissiontype = zeros(4, year) #type yearly emissions
result_REcurtail = zeros(1,year*Hours)
result_MaxRE = zeros(1,year*Hours)
result_trueprofit = zeros(Ngen, year*Hours)
result_trueyearprofit = zeros(Ngen, year)
result_truenetprofit = zeros(Ngen, year)

#results of fixed model
result_obj_f = zeros(1, year*Hours)
result_gen_fixed = zeros(Ngen, year*Hours)
result_UC_fixed = zeros(Ngen, year*Hours)
result_reserve_fixed = zeros(Ngen, year*Hours)
result_bus_fixed = zeros(Nbus, year*Hours)
result_line_fixed = zeros(Nline*2, year*Hours)
result_ES_fixed = zeros(1, year*Hours)

# track retirement
RetireID = zeros(1,year)
RetireIDforced = zeros(1,year)
ExistID = collect(1:1:Ngen)
ExistID_fossil = collect(1:1:Ncoal+Ncc+Nct+Noil)
ESmax = zeros(1,year*Hours)
NewRE = zeros(1,year)
TotalRE = zeros(1,1)


for i = 1:2 #11 years
    for j = 1:Totalsolve #solve for one day per run
        TotalRE = sum(NewRE) #calculate total RE capacity
        Rreq = 0.03*HourlyLoad[(j-1)*Hourspersolve+1:(j-1)*Hourspersolve+Hourspersolve]/baseMVA .+ 0.05*TotalRE*REhourlyCF[(j-1)*Hourspersolve+1:(j-1)*Hourspersolve+Hourspersolve] #set reserve requirement as a function of load and Rreq
        Loadpersolve = HourlyLoad[(j-1)*Hourspersolve+1:(j-1)*Hourspersolve+Hourspersolve]
        for t in 1:Hourspersolve
            set_normalized_rhs(rglower[t], Rreq[t]) 
            set_normalized_rhs(rgupper_ES[t], Rreq[t]*ESrate*(i-1))
            set_normalized_rhs(pgnodal[t], Loadpersolve[t]/baseMVA) 
            set_normalized_coefficient(pgupper[17,t], UC[17,t], TotalRE*REhourlyCF[(j-1)*Hourspersolve+t])
            set_normalized_coefficient(rgupper[17,t], UC[17,t], TotalRE*REhourlyCF[(j-1)*Hourspersolve+t]*RegRE)
        end
        # for retireunit in RetireID
        #     if retireunit != 0
        #         for t in 1:Hourspersolve
        #             fix(UC[retireunit,t], 0; force = true)
        #             set_normalized_coefficient(pgupper[17,t], UC[17,t], TotalRE*REhourlyCF[(j-1)*Hourspersolve+t])
        #             set_normalized_coefficient(rgupper[17,t], UC[17,t], TotalRE*REhourlyCF[(j-1)*Hourspersolve+t]*RegRE)
        #         end
        #     end
        # end
        # for b in RetireIDforced[1:(i-1)]
        #     m = findall(x -> x==b, RetireIDforced[1:(i-1)])
        #     if m[1] < i
        #         if b != 0
        #             for t in 1:Hourspersolve
        #                 fix(UC[b,t], 0; force = true)
        #                 fix(UC_f[b,t], 0; force = true)
        #                 set_normalized_coefficient(pgupper[b+17,t], UC[b+17,t], -ref[:gen][b+17]["pmax"]*REhourlyCF[(j-1)*Hourspersolve+t])
        #                 set_normalized_coefficient(rgupper[b+17,t], UC[b+17,t], -ref[:gen][b+17]["pmax"]*REhourlyCF[(j-1)*Hourspersolve+t]*RegRE)
        #                 set_normalized_coefficient(pgupper_f[b+17,t], UC_f[b+17,t], -ref[:gen][b+17]["pmax"]*REhourlyCF[(j-1)*Hourspersolve+t])
        #                 set_normalized_coefficient(rgupper_f[b+17,t], UC_f[b+17,t], -ref[:gen][b+17]["pmax"]*REhourlyCF[(j-1)*Hourspersolve+t]*RegRE)
        #             end
        #         end
        #     end
        # end

        optimize!(PSdecarbonization)
        result_obj[(i-1)*Totalsolve + j] = JuMP.objective_value(PSdecarbonization)
        for s = 1:Ngen
            result_gen[s,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(Pg[s,:])*baseMVA
            result_UC[s,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(UC[s,:]) 
            result_reserve[s,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(Rg[s,:])*baseMVA
        end
        result_ES[1,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(Rg_ES)*baseMVA
        result_loadloss[1,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(loadloss).*baseMVA
        result_reserveloss[1,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(reserveloss).*baseMVA

        #solve with fixed UC
        for k = 1:Ngen
            for t in 1:Hourspersolve
                if abs(value.(UC[k,t])-0) < abs(value.(UC[k,t])-1)
                    set_normalized_rhs(unitc_f[k,t], 0)
                else
                    set_normalized_rhs(unitc_f[k,t], 1)
                end
            end
        end
        for t in 1:Hourspersolve
            set_normalized_rhs(rglower_f[t], Rreq[t]) 
            set_normalized_rhs(rgupper_ES_f[t], Rreq[t]*ESrate*(i-1)) 
            set_normalized_rhs(pgnodal_f[t], Loadpersolve[t]/baseMVA) 
            set_normalized_coefficient(pgupper_f[17,t], UC_f[17,t], TotalRE*REhourlyCF[(j-1)*Hourspersolve+t])
            set_normalized_coefficient(rgupper_f[17,t], UC_f[17,t], TotalRE*REhourlyCF[(j-1)*Hourspersolve+t]*RegRE)
        end
        # for retireunit in RetireID
        #     if a != 0
        #         for t in 1:Hourspersolve
        #             set_normalized_coefficient(pgupper_f[17,t], UC_f[17,t], TotalRE*REhourlyCF[(j-1)*Hourspersolve+t])
        #             set_normalized_coefficient(rgupper_f[17,t], UC_f[17,t], TotalRE*REhourlyCF[(j-1)*Hourspersolve+t]*RegRE)
        #         end
        #     end
        # end
        optimize!(Fixedmodel)
        result_obj_f[(i-1)*Totalsolve + j] = JuMP.objective_value(Fixedmodel)
        for s = 1:Ngen
            result_gen_fixed[s,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(Pg_f[s,:])*baseMVA
            result_UC_fixed[s,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(UC_f[s,:])
            result_reserve_fixed[s,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(Rg_f[s,:])*baseMVA
        end
        result_ES_fixed[1,(i-1)*Hours+(j-1)*Hourspersolve+1:(i-1)*Hours+(j-1)*Hourspersolve+Hourspersolve] = value.(Rg_ES_f)*baseMVA
        for t in 1:Hourspersolve
            result_dual[1,(i-1)*Hours+(j-1)*Hourspersolve+t] = dual(pgnodal_f[t])./baseMVA
            result_Rprice[1,(i-1)*Hours+(j-1)*Hourspersolve+t] = dual(rglower_f[t])./baseMVA
        end
    end #for j
    
    #calculate profit and emission at each hour
    for s = 1:Ngen
        g = ref[:gen][s]["gen_bus"]
        result_gencost[s,(i-1)*Hours+1:(i-1)*Hours+Hours] = ref[:gen][s]["VOM"] * result_gen[s,(i-1)*Hours+1:(i-1)*Hours+Hours] + (ref[:gen][s]["fprice"]+ref[:gen][s]["ER"]*Ctax)*
                (ref[:gen][s]["cost"][1]*(result_gen[s,(i-1)*Hours+1:(i-1)*Hours+Hours]./100).^2 + ref[:gen][s]["cost"][2] * (result_gen[s,(i-1)*Hours+1:(i-1)*Hours+Hours]./100) + result_UC[s,(i-1)*Hours+1:(i-1)*Hours+Hours]*ref[:gen][s]["cost"][3])
        result_genCTcost[s,(i-1)*Hours+1:(i-1)*Hours+Hours] = ref[:gen][s]["ER"]*Ctax*(ref[:gen][s]["cost"][1]*(result_gen[s,(i-1)*Hours+1:(i-1)*Hours+Hours]./100).^2 + ref[:gen][s]["cost"][2] * (result_gen[s,(i-1)*Hours+1:(i-1)*Hours+Hours]./100) + result_UC[s,(i-1)*Hours+1:(i-1)*Hours+Hours]*ref[:gen][s]["cost"][3])
        result_reservecost[s,(i-1)*Hours+1:(i-1)*Hours+Hours] = ref[:gen][s]["Rcost"] * result_reserve[s,(i-1)*Hours+1:(i-1)*Hours+Hours]
        result_genrevenue[s,(i-1)*Hours+1:(i-1)*Hours+Hours] = result_gen[s,(i-1)*Hours+1:(i-1)*Hours+Hours] .* result_dual[1,(i-1)*Hours+1:(i-1)*Hours+Hours]
        result_reserverevenue[s,(i-1)*Hours+1:(i-1)*Hours+Hours] = result_reserve[s,(i-1)*Hours+1:(i-1)*Hours+Hours] .* result_Rprice[1,(i-1)*Hours+1:(i-1)*Hours+Hours]
        result_profit[s,(i-1)*Hours+1:(i-1)*Hours+Hours] = result_genrevenue[s,(i-1)*Hours+1:(i-1)*Hours+Hours] + result_reserverevenue[s,(i-1)*Hours+1:(i-1)*Hours+Hours] - result_gencost[s,(i-1)*Hours+1:(i-1)*Hours+Hours] - result_reservecost[s,(i-1)*Hours+1:(i-1)*Hours+Hours]
        result_genemission[s,(i-1)*Hours+1:(i-1)*Hours+Hours] = ref[:gen][s]["ER"] * (ref[:gen][s]["cost"][1]*(result_gen[s,(i-1)*Hours+1:(i-1)*Hours+Hours]./100).^2 + ref[:gen][s]["cost"][2] *(result_gen[s,(i-1)*Hours+1:(i-1)*Hours+Hours]./100) + result_UC[s,(i-1)*Hours+1:(i-1)*Hours+Hours]*ref[:gen][s]["cost"][3])
    end

    for s = 1:Ngen
        for i = 1:year*Hours
            if result_dual[i] > 200 || result_Rprice[i] > 200 ## the shadow prices are not true energy/reserve price when there are loadloss and/or reserveloss. Calculation for generator retirement should exclude these profits
                result_trueprofit[s,i] = 0
            else
                result_trueprofit[s,i] = result_profit[s,i]
            end
        end
    end

    #calculate RE curtailment
    result_MaxRE[1,(i-1)*Hours+1:(i-1)*Hours+Hours] = baseMVA*TotalRE*REhourlyCF
    result_REcurtail[1,(i-1)*Hours+1:(i-1)*Hours+Hours] = baseMVA*TotalRE*REhourlyCF.-sum(result_gen[17,(i-1)*Hours+1:(i-1)*Hours+Hours],dims=1)

    #calculate yearly ES regulation
    result_yearES[1,i] = sum(result_ES[1,((i-1)*Hours+1):((i-1)*Hours+Hours)])

    #calculate yearly profit, net profit and yearly emission
    for s = 1:Ngen
        result_yeargen[s,i] = sum(result_gen[s,((i-1)*Hours+1):((i-1)*Hours+Hours)])
        result_yearreserve[s,i] = sum(result_reserve[s,((i-1)*Hours+1):((i-1)*Hours+Hours)])
        result_yearCTcost[s,i] = sum(result_genCTcost[s,((i-1)*Hours+1):((i-1)*Hours+Hours)])
        result_yearprofit[s,i] = sum(result_profit[s,((i-1)*Hours+1):((i-1)*Hours+Hours)])
        result_netprofit[s,i] = result_yearprofit[s,i] - FOM[s]

        result_trueyearprofit[s,i] = sum(result_trueprofit[s,((i-1)*Hours+1):((i-1)*Hours+Hours)])
        result_truenetprofit[s,i] = result_trueyearprofit[s,i] - FOM[s]

        result_yeargen_emission[s,i] = sum(result_genemission[s,((i-1)*Hours+1):((i-1)*Hours+Hours)])
    end

    result_yeargen_emissiontype[:,i] = [sum(result_yeargen_emission[1:Ncoal,i],dims = 1);sum(result_yeargen_emission[Ncoal+1:Ncoal+Ncc,i],dims = 1);sum(result_yeargen_emission[Ncoal+Ncc+1:Ncoal+Ncc+Nct,i],dims = 1);result_yeargen_emission[Ncoal+Ncc+Nct+Noil,i]]

    #calculate yearly system cost (objective)
    result_yearobj[i] = sum(result_obj[((i-1)*Totalsolve+1):((i-1)*Totalsolve+Totalsolve)])

################################################################################Forced retirement
    if forceunit != 0
        if i == forceyear
            for t in 1:Hourspersolve
                fix(UC[forceunit,t], 0) #force the UC variable of the retired unit to be zero
            end
            filter!(x->x≠forceunit,ExistID) #filter out retired unit from exist ID list
            filter!(x->x≠forceunit,ExistID_fossil) #filter out retired unit from exist ID list

            ref[:gen][17]["pmax"] = TotalRE + ref[:gen][forceunit]["pmax"]./REyearlyCF
            NewRE[1,i] = NewRE[1,i] + ref[:gen][forceunit]["pmax"]./REyearlyCF
        end
    end
################################################################################Forced retirement

################################################################################Economic retirement
    #find the smallest netprofit among existing units
    global Idx = findall(x -> x == minimum([result_truenetprofit[s,i] for s in ExistID_fossil]), result_truenetprofit[1:16,i])
    if length(Idx) > 1
        global retireunit = Idx[Idx .∉ Ref(RetireID)][1]
    else
        global retireunit = Idx[1]
    end #find out the only one minimum unit

    if result_truenetprofit[retireunit,i] < 0.00
        for t in 1:Hourspersolve
            fix(UC[retireunit,t], 0; force = true)
        end
        filter!(x->x≠retireunit,ExistID) 
        filter!(x->x≠retireunit,ExistID_fossil) 
        RetireID[i] = retireunit 
  
        ref[:gen][17]["pmax"] = TotalRE + ref[:gen][retireunit]["pmax"]./REyearlyCF
        NewRE[1,i] = NewRE[1,i] + ref[:gen][retireunit]["pmax"]./REyearlyCF
    end
###############################################################################Economic retirement
end #for i

## more results calculation
result_yearemission = sum(result_yeargen_emission,dims = 1)
result_emission = sum(result_yearemission, dims = 2)

## plotting example
#Emission plot
plot_emission = plot(collect(0:1:year-1), result_yearemission',
    xlabel = "Year", ylabel = "Emission (metric ton)",
    legendfontsize = 6,
    guidefontsize = 8,
    tickfontsize = 6,
    xticks = (collect(0:1:year),collect(0:1:year)),
    margin = -1mm,
    size = (600,400))

display(plot_emission)


#yearly plot
plotyear = 4
plot(HourlyLoad[1:Hours], label = "Load")
plot!(sum(result_gen[1:6, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "Coal")
plot!(sum(result_gen[7:9, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "CC")
plot!(sum(result_gen[10:15, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "CT")
plot!(sum(result_gen[16, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "Oil")
plot!(sum(result_gen[17, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "RE")

plotyear = 2
plot(0.03*HourlyLoad[1:Hours] + 0.05*100*sum(NewRE[1:(plotyear-1)])*REhourlyCF[1:Hours], label = "Rreq")
plot!(sum(result_reserve[1:6, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "Coal")
plot!(sum(result_reserve[7:9, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "CC")
plot!(sum(result_reserve[10:15, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "CT")
plot!(sum(result_reserve[16, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "Oil")
plot!(sum(result_reserve[17, (plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],dims=1)',label = "RE")
plot!(result_ES[(plotyear-1)*Hours+1:(plotyear-1)*Hours+Hours],label = "ES")




