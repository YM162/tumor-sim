
#We create the Cell agent
@agent Cell GridAgent{3} begin
        time_alive::Int  # Time the cell has been alive
        near_cells::Number # Number of cells in the neighborhood
        genotype::BitArray # Genotype of the cell
        phylogeny::Array{Int} # Phylogeny of the cell
end

#We initialize the model according to some parameters.
function  model_init(;seed,pr,dr,mr,fitness,scenario,treatment)
    #We need to do this to reuse the treatment in paramscan
    treatment = Treatment(treatment.detecting_size,
                            treatment.starting_size,
                            treatment.pausing_size,
                            treatment.resistance_gene,
                            treatment.kill_rate,
                            treatment.active,
                            treatment.detected)

    x = scenario.x
    y = scenario.y
    z = scenario.z
    cell_pos = scenario.cell_pos
    wall_pos = scenario.wall_pos
    current_size=length(cell_pos)

    ngenes=length(collect(keys(fitness))[1])
    
    fitness = Dict(zip([BitArray(i) for i in keys(fitness)],[fitness[i] for i in keys(fitness)]))
    fitness=DefaultDict(0,fitness)

    rng = MersenneTwister(seed)

    if y!=0 && z!=0
        space = GridSpace((x, y, z),periodic=false)

        #we create the walls visualization matrix
        wall_matrix=zeros(Int8, x, y, z)
        for t in wall_pos
            i,j,k=t
            wall_matrix[i,j,k]=1
        end

        properties=@dict(pr,dr,mr,fitness,wall_pos,wall_matrix,treatment,scenario,current_size)
        model = ABM(Cell, space;properties, rng) 
        #we create each cell
        for cell in cell_pos
            add_agent!((cell[1],cell[2],cell[3]),model,0,0,BitArray([false for x in 1:ngenes]),[]) # With this one we use the scenario
        end
    else
        space = GridSpace((1,1,1),periodic=false)
        wall_matrix=zeros(Int8, 1)
        properties=@dict(pr,dr,mr,fitness,wall_pos,wall_matrix,treatment,scenario,current_size)
        model = ABM(Cell, space;properties, rng) 
        for cell in cell_pos
            add_agent!(model,0,0,BitArray([false for x in 1:ngenes]),[]) # With this one we use the scenario
        end
    end

    return model
end

#Function to get the number of cells "near" each cell.
function get_near!(agent,model)
    if model.scenario.z==0 #If we are in 0D

        bin = Binomial(length(model.agents),1/model.scenario.x)
        return (length(model.agents)/model.scenario.x)/(1-pdf(bin,0)) #We calculate the mean number of cells in each cell´s space using a binomial distribution.

    end
    return length(ids_in_position(agent, model))
end

#Step evey agent, updating its parameters and then reproducing, moving and dying.
function agent_step!(agent, model)
    agent.time_alive += 1
    agent.near_cells = get_near!(agent,model)
    
    if reproduce!(agent, model) #We want to stop doing things if the cell has died.
        return
    end
    if model.scenario.z!=0 #We dont move if we are in 0D
        move!(agent, model)
    end
    if die!(agent, model)
        return
    end
end

#We use the model step to evaluate the treatment
function model_step!(model)
    current_size = length(model.agents)
    model.current_size = current_size
    if model.treatment.detected
        if current_size < model.treatment.pausing_size
            model.treatment.active = false
        end
        if current_size > model.treatment.starting_size
            model.treatment.active = true
        end
    else
        if current_size > model.treatment.detecting_size
            model.treatment.detected = true
        end
    end
end

#We stop if any of this conditions are met.
function create_stop_function(steps,stop_size)
    function step(model,s)
        if length(model.agents)==0
            return true
        end
        if length(model.agents)>=stop_size && model.treatment.detected
            return true
        end
        if s==steps
            return true
        end
            return false
    end
    return step
end

#If the cell is susceptible to the treatment, and treatment is active, it dies. Returns true if the cell has dies
function treat!(agent,model)
    if model.treatment.active && agent.genotype[model.treatment.resistance_gene]!=1
        kill_agent!(agent,model)
        return true
    end
    return false
end

#with a probability p choose a random non mutated gene and mutate it.
function mutate!(agent,model)
    genes=findall(agent.genotype .!=1)
    if genes!=[] && rand(model.rng) < model.mr
        gene = rand(model.rng,genes)
        agent.genotype[gene]=true
        push!(agent.phylogeny,gene)
    end
end

#Reproduce, creating a new cell in the same space with a probability that decreases with how many cells are already in its space.
#With a probability (the kill rate of the treatment), the cell is subjected to a treatment check.
#Returns true if the cell has died.
function reproduce!(agent,model)
    pr = model.pr*model.fitness[agent.genotype]
    pid = agent.pos
    newgenom = copy(agent.genotype)
    newphylo = copy(agent.phylogeny)
    prob = pr/(get_near!(agent,model)^2)
    if rand(model.rng) < prob/(1+prob)
        if rand(model.rng) < model.treatment.kill_rate
            if treat!(agent,model)
                return true
            end
        end
        newagent = add_agent!(pid,model,0,0,newgenom,newphylo)
        mutate!(newagent,model)
        kill_non_viable!(newagent, model)

        mutate!(agent,model)
        if kill_non_viable!(agent, model)
            return true
        end
    end
    return false
end

#Move every cell to a random nearby space ONLY if your space is "crowded", crowded for example is more than 1 cell in your space 
function move!(agent, model)
    pos = agent.pos
    nearby = [x for x in nearby_positions(agent,model,1)]

    setdiff!(nearby,model.wall_pos)
    nearby_density = [1/(length(ids_in_position(x,model))+1) for x in nearby]
    
    push!(nearby,pos)
    push!(nearby_density,1/length(ids_in_position(agent,model)))

    newpos = sample(model.rng, nearby, Weights(nearby_density))
    if length(ids_in_position(agent, model)) > 1
        move_agent!(agent,newpos, model)
    end
end

#die, with a probability that increases with the number of cells that are in its space. returns true if the cell has died.
function die!(agent, model)
    prob = model.dr*(get_near!(agent,model)^2)
    if rand(model.rng) < prob/(1+prob)
        kill_agent!(agent, model)
        return true
    end
    return false
end

#we kill all non viable agents instantly to make our data cleaner
function kill_non_viable!(agent, model)
    if !(agent.genotype in keys(model.fitness))
        kill_agent!(agent,model)
        return true
    end
    return false
end