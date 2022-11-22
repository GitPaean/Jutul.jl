export sort_secondary_variables!, build_variable_graph
export @jutul_secondary
export jutul_secondary

"""
Designate the function as updating a secondary variable.

The function is then declared, in addition to helpers that allows
checking what the dependencies are and unpacking the dependencies from state.

If we define the following function annotated with the macro:
@jutul_secondary function some_fn!(target, var::MyVarType, model, a, b, c)
    @. target = a + b / c
end

The macro also defines: 
function get_dependencies(var::MyVarType, model)
   return (:a, :b, :c)
end

function update_secondary_variable!(array_target, var::MyVarType, model, state, ix)
    some_fn!(array_target, var, model, state.a, state.b, state.c, ix)
end

Note that the names input of some arguments matter, as these will be fetched from state.
"""
macro jutul_secondary(ex)
    def = splitdef(ex)
    args = def[:args]
    # Define filters to strip the type spec (if any)
    function myfilter(x::Symbol)
        x
    end
    function myfilter(x::Expr)
        x.args[1]
    end

    deps = tuple(map(myfilter, args[4:end-1])...)
    # Pick variable + model
    variable_sym = args[2]
    model_sym = args[3]
    @debug "Building evaluator for $variable_sym"

    # Define get_dependencies function
    dep_def = deepcopy(def)
    dep_def[:name] = :get_dependencies
    dep_def[:args] = [variable_sym, model_sym]
    dep_def[:body] = deps
    ex_dep = combinedef(dep_def)
    # Define update_as_secondary! function
    upd_def = deepcopy(def)
    upd_def[:name] = :update_secondary_variable!
    upd_def[:args] = [:array_target, variable_sym, model_sym, :state, :ix]
    # value, var, model, arg1, arg2
    tmp = "$(def[:name])(array_target, "
    tmp *= String(myfilter(variable_sym))
    tmp *= ", "
    tmp *= String(myfilter(model_sym))

    for s in deps
        tmp *= ", state."*String(s)
    end
    tmp *= ", ix)"
    upd_def[:body] = Meta.parse(tmp)
    ex_upd = combinedef(upd_def)

    quote
        $ex
        $ex_dep
        $ex_upd
    end |> esc 
end

function update_secondary_variables!(storage, model)
    update_secondary_variables_state!(storage.state, model)
end

function update_secondary_variables!(storage, model, is_state0::Bool)
    if is_state0
        s = storage.state0
    else
        s = storage.state
    end
    update_secondary_variables_state!(s, model)
end

function update_secondary_variables_state!(state, model)
    ctx = model.context
    N = nthreads(ctx)
    if N == 1
        for (symbol, var) in model.secondary_variables
            @timeit "$symbol" begin
                v = state[symbol]
                ix = entity_eachindex(v)
                update_secondary_variable!(v, var, model, state, ix)
            end
        end
    else
        Threads.@threads for i in 1:N
            for (symbol, var) in model.secondary_variables
                v = state[symbol]
                ix = entity_eachindex(v, i, N)
                update_secondary_variable!(v, var, model, state, ix)
            end
        end
    end
end

# Initializers
function select_secondary_variables!(model)
    svars = model.secondary_variables
    select_secondary_variables!(svars, model.domain, model)
    select_secondary_variables!(svars, model.system, model)
    select_secondary_variables!(svars, model.formulation, model)
end

select_secondary_variables!(svars, ::JutulSystem, model) = nothing
select_secondary_variables!(svars, ::JutulFormulation, model) = nothing

function select_primary_variables!(model::SimulationModel)
    pvars = model.primary_variables
    select_primary_variables!(pvars, model.domain, model)
    select_primary_variables!(pvars, model.system, model)
    select_primary_variables!(pvars, model.formulation, model)
end

select_primary_variables!(vars, ::JutulFormulation, model) = nothing

function select_parameters!(model::SimulationModel)
    prm = model.parameters
    select_parameters!(prm, model.domain, model)
    select_parameters!(prm, model.system, model)
    select_parameters!(prm, model.formulation, model)
end

select_parameters!(prm, ::JutulSystem, model) = nothing
select_parameters!(prm, ::JutulFormulation, model) = nothing

function select_equations!(model::SimulationModel)
    eqs = model.equations
    select_equations!(eqs, model.domain, model)
    select_equations!(eqs, model.system, model)
    select_equations!(eqs, model.formulation, model)
end

select_equations!(eqs, ::JutulSystem, model) = nothing
select_equations!(eqs, ::JutulFormulation, model) = nothing

function select_minimum_output_variables!(model)
    # Minimum is always all primary variables (for restarting) plus anything added
    outputs = model.output_variables
    for k in keys(model.primary_variables)
        push!(outputs, k)
    end
    select_minimum_output_variables!(outputs, model.domain, model)
    select_minimum_output_variables!(outputs, model.system, model)
    select_minimum_output_variables!(outputs, model.formulation, model)
end

select_minimum_output_variables!(outputs, ::Any, model) = nothing

"""
Get dependencies of variable when viewed as a secondary variable. Normally autogenerated with @jutul_secondary
"""
function get_dependencies(svar, model)
    Symbol[]
end

export update_secondary_variable!
"""
Update a secondary variable. Normally autogenerated with @jutul_secondary
"""
function update_secondary_variable!(x, var, model, parameters, state, arg...)
    error("update_secondary_variable! not implemented for $(typeof(var)).")
end

function map_level(primary_variables, secondary_variables, output_level)
    pkeys = [i for i in keys(primary_variables)]
    skeys = [i for i in keys(secondary_variables)]
    if output_level == :all
        out = vcat(pkeys, skeys)
    elseif output_level == :primary_variables
        out = pkeys
    elseif output_level == :secondary_variables
        out = skeys
    else
        out = [output_level]
    end
end

function select_output_variables!(model, output_level = :primary_variables)
    select_minimum_output_variables!(model)
    outputs = model.output_variables
    if !isnothing(output_level)
        if isa(output_level, Symbol)
            output_level  = [output_level]
        end
        for levels in output_level
            mapped = map_level(model.primary_variables, model.secondary_variables, levels)
            for v in mapped
                push!(outputs, v)
            end
        end
    end
    unique!(outputs)
end

function sort_secondary_variables!(model::JutulModel)
    # Do nothing for general case.
end

function build_variable_graph(model, primary = model.primary_variables, secondary = model.secondary_variables, param = model.parameters; to_graph = false)
    edges = []
    nodes = Vector{Symbol}()
    for key in keys(primary)
        push!(nodes, key)
        push!(edges, []) # No dependencies for primary variables.
    end
    for key in keys(param)
        push!(nodes, key)
        push!(edges, []) # No dependencies for parameters - they are static.
    end
    for (key, var) in secondary
        dep = get_dependencies(var, model)
        push!(nodes, key)
        push!(edges, dep)
    end
    if to_graph
        n = length(nodes)
        graph = SimpleDiGraph(n)
        for (i, edge) in enumerate(edges)
            for d in edge
                pos = findall(nodes .== d)
                @assert length(pos) == 1 "Symbol $d must appear exactly once in secondary variables or parameters, found $(length(pos)) entries. Declared secondary/parameters:\n $symbols. Declared dependencies:\n $deps"
                add_edge!(graph, i, pos[])
            end
        end
        return (graph = reverse(graph), nodes = nodes, edges = edges)
    else
        return (nodes, edges)
    end
end

function sort_secondary_variables!(model::SimulationModel)
    primary = model.primary_variables
    secondary = model.secondary_variables
    param = model.parameters

    isect = intersect(keys(primary), keys(secondary))
    if length(isect) > 0
        error("$isect found in both primary and secondary variables.")
    end
    isect = intersect(keys(primary), keys(param))
    if length(isect) > 0
        error("$isect found in both primary variables and parameters.")
    end
    isect = intersect(keys(param), keys(secondary))
    if length(isect) > 0
        error("$isect found in both parameters and secondary variables.")
    end
    nodes, edges = build_variable_graph(model, primary, secondary, param)
    order = sort_symbols(nodes, edges)
    @debug "Variable ordering determined: $(nodes[order])"
    np = length(primary) + length(param)
    for i in 1:np
        @assert order[i] <= np "Primary variables and parameters should come in the first $np entries in ordering. Something is very wrong."
    end
    # Skip primary variable indices - these always come first.
    order = order[order .> np]
    # Offset by primary variables
    @. order -= np
    @. secondary.keys = secondary.keys[order]
    @. secondary.vals = secondary.vals[order]
    OrderedCollections.rehash!(secondary)
    return model
end

function sort_symbols(symbols, deps)
    @assert length(symbols) == length(deps)
    n = length(symbols)
    graph = SimpleDiGraph(n)
    for (i, dep) in enumerate(deps)
        for d in dep
            pos = findall(symbols .== d)
            if length(pos) != 1
                println("Symbol $d must appear exactly once in secondary variables or parameters, found $(length(pos)) entries. Dependencies on $d:")
                for (si, di) in zip(symbols, deps)
                    if d in di
                        println("$si depends on $di")
                    end
                end
                error("Unable to continue.")
            end
            add_edge!(graph, i, pos[])
        end
    end
    reverse(topological_sort_by_dfs(graph))
end

