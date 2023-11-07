# PSdecarbonization

## Four-hour model
The optimization model is built using [PowerModels](https://lanl-ansi.github.io/PowerModels.jl/stable/) and [JuMP](https://jump.dev/JuMP.jl/stable/). Input data is provided in [Systeminfo](https://github.com/JPengUMich/PSdecarbonization/blob/main/4-hour%20model/Systeminfo.m). The simulation is performed for four representation hours in a year for 11 years. [Gurobi](https://www.gurobi.com/downloads/) license or other suitable MILP solvers are required.

## 8760-hour model
Based on the 4-hour model, the simulation is performed for 8760 hours (24 hours per run) in a year for 11 years. The hourly data of load and renewables are provided in [8760data](https://github.com/JPengUMich/PSdecarbonization/blob/main/8760-hour%20model/8760data.csv) and supplementary results are provided in [Supprting Information](https://github.com/JPengUMich/PSdecarbonization/blob/main/8760-hour%20model/Supporting%20Information.pdf).
