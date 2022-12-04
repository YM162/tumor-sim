using Distributed

@everywhere using DrWatson
@everywhere @quickactivate "TumorSim"

@everywhere using TumorSim

using ProgressMeter
#With the same fitness we can change the cost of resistance
fitness1=Dict([0,0,0]=>1, 
                [1,0,0]=>1.3,
                [0,1,0]=>1.2,
                [1,1,0]=>1.5,
                [1,1,1]=>0.6)

fitness2=Dict([0,0,0]=>1, 
                [1,0,0]=>1.3,
                [0,1,0]=>1.2,
                [1,1,0]=>1.5,
                [1,1,1]=>0.8)

fitness3=Dict([0,0,0]=>1, 
                [1,0,0]=>1.3,
                [0,1,0]=>1.2,
                [1,1,0]=>1.5,
                [1,1,1]=>1)

fitness4=Dict([0,0,0]=>1, 
                [1,0,0]=>1.3,
                [0,1,0]=>1.2,
                [1,1,0]=>1.5,
                [1,1,1]=>1.2)

fitness5=Dict([0,0,0]=>1, 
                [1,0,0]=>1.3,
                [0,1,0]=>1.2,
                [1,1,0]=>1.5,
                [1,1,1]=>1.5)
                
#We test the dimensionality.
scenario_0D = create_scenario((1000000),10)
scenario_1D = create_scenario((1000000,),10,"center")
scenario_2D = create_scenario((1000,1000),10,"center")
scenario_3D = create_scenario((100,100,100),10,"center")

#We test adaptive and continuous therapy
adaptive_therapy = create_treatment(3000, 2000, 1000, 3, 0.75) 
continuous_therapy = create_treatment(3000, 2000, 0, 3, 0.75) 

#This would be cool to do, but we need the cluster, because its 5.000.000 simulations for each fitness landscape. Would take 10 months on my computer.
parameters = Dict(
    "pr" => [0.01,0.02,0.03,0,04,0.05],
    "dr" => [0,0.2,0.4,0.6,0.8],
    "mr" => [0.001,0.005,0.01,0.05,0.1],   
    "scenario" => [scenario_0D,scenario_1D,scenario_2D,scenario_3D], 
    "fitness" => [fitness1,fitness2,fitness3,fitness4,fitness5],
    "treatment" => [adaptive_therapy,continuous_therapy],
    "seed" => map(abs,rand(Int64,1))
)

parameters = Dict(
    "pr" => 0.027,
    "dr" => 0.55,
    "mr" => 0.01,   
    "scenario" => scenario_3D, 
    "fitness" => fitness4,
    "treatment" => [adaptive_therapy,continuous_therapy],
    "seed" => map(abs,rand(Int64,10))
)
parameter_combinations = dict_list(parameters)

steps=3000

results = @showprogress pmap(simulate,parameter_combinations,fill(steps,length(parameter_combinations)))

for (i, d) in enumerate(parameter_combinations)
    safesave(datadir("simulations", savename(results[i], "jld2")), results[i])
end