#We import everything we need
cd(@__DIR__) #src
using Agents, Random
using Agents.DataFrames, Agents.Graphs
using Distributions: Poisson, DiscreteNonParametric
using DrWatson: @dict
using CairoMakie
CairoMakie.activate!()


using InteractiveDynamics
using StatsBase
using ColorSchemes
using DataStructures
using VegaLite
using DataFrames

using RCall




#We create the Cell agent
@agent Cell GridAgent{2} begin
        time_alive::Int  # Time the cell has been alive
        near_cells::Int # Number of cells in the neighborhood
        genotype::BitArray # Genotype of the cell
end

#We initialize the model according to some parameters.
function  model_init(;pr,dr,mr,seed,l,n0,ngenes,fitness)
    
    rng = MersenneTwister(seed)

    space = GridSpace((l, l))
    properties=@dict(ngenes,pr,dr,mr,fitness)
    model = ABM(Cell, space;properties, rng) 

    for i in 1:n0
        #add_agent!(model,0,0,BitArray([false for x in 1:ngenes])) #With this one we generate at random over the grid
        add_agent!((Int(floor(l/2)),Int(floor(l/2))),model,0,0,BitArray([false for x in 1:ngenes])) #With this we generate all of them at the middle point
    end
    return model
end

#Function to get the number of cells "near" each cell. As i dont know what should count as near (only the space or a mean of the 8 surrounding spaces? for example) i prefer to define it in a single place and then change it.
function get_near!(agent,model)
    length(ids_in_position(agent, model))
end

#Step evey agent, updating its parameters and then reproducing, moving and dying.
function agent_step!(agent, model)
    if agent.time_alive == 0
        mutate!(agent,model)
    end
    agent.time_alive += 1
    agent.near_cells = get_near!(agent,model)
    reproduce!(agent, model)
    move!(agent, model)
    die!(agent, model)
end

#with a probability p choose a random non mutated gene and mutate it.
function mutate!(agent,model)
    genes=findall(agent.genotype .!=1)
    if genes!=[] && rand(model.rng) < model.mr
        agent.genotype[rand(model.rng,genes)]=true
    end
end

#reproduce, creating a new cell in the same space with a probability that decreases with how many cells are already in its space
function reproduce!(agent,model)
    pr = model.pr*model.fitness[bit_2_int(agent.genotype)]
    pid = agent.pos
    newgenom = copy(agent.genotype)
    if rand(model.rng) < pr/(get_near!(agent,model)^2)
        add_agent!(pid,model,0,0,newgenom)
    end
end

#Move every cell to a random nearby space ONLY if your space is "crowded", crowded for example is more than 1 cell in your space 
function move!(agent, model)
    pos = agent.pos
    nearby = [x for x in nearby_positions(agent,model,1)]
    newpos = rand(model.rng, nearby)
    if length(ids_in_position(agent, model)) > 1
        move_agent!(agent,newpos, model)
    end
end

#die, with a probability that increases with the number of cells that are in its space.
function die!(agent, model)
    pos = agent.pos
    nearby = [x for x in nearby_positions(agent,model,1)]
    if rand(model.rng) < model.dr*(get_near!(agent,model)^2)
        kill_agent!(agent, model)
    end
end

#A generator that returns a list of functions that each get the number of cells of each genotype given a number of genes.
function genotype_fraction_function_generator(ngenes)
    functions = []
    for i in 0:((2^ngenes)-1)
        compare = reverse(digits(i, base=2, pad=ngenes))
        func = function get_perc(x)
            len = length(findall([string(y)[5:end] for y in x] .== string(compare)))
            return len
        end
        push!(functions,func)
    end
    return functions
end

#Function to create a random fitness landscape using the OncoSimulR library.
#How can i feed it a seed??
function OncoSimulR_rfitness(;g,c,sd)
    R"library(OncoSimulR)"
    fitness = R"rfitness(g=$g ,c=$c ,sd=$sd )"
    rows=2^g
    dictionary=Dict()
    for i in 1:rows
        genotype=BitArray([])
        for j in 1:g
            push!(genotype,fitness[i,j])
        end
        push!(dictionary,(bit_2_int(genotype)=>Float64(fitness[i,g+1])))
    end
    return dictionary
end

#Function to go from BitArray to Int. Taken from https://discourse.julialang.org/t/parse-an-array-of-bits-bitarray-to-an-integer/42361/5
function bit_2_int(arr)
    arr = reverse(arr)
    sum(((i, x),) -> Int(x) << ((i-1) * sizeof(x)), enumerate(arr.chunks))
end