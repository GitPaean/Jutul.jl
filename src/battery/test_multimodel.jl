#=
Electro-Chemical component
A component with electric potential, concentration and temperature
The different potentials are independent (diagonal onsager matrix),
and conductivity, diffusivity is constant.
=#
using Terv
using MAT
using Plots
ENV["JULIA_DEBUG"] = Terv;

##
function make_system(exported,sys)
    name="model1d"
    fn = string(dirname(pathof(Terv)), "/../data/models/", name, ".mat")
    exported_all = MAT.matread(fn)
    exported = exported_all["model"]["NegativeElectrode"]["CurrentCollector"];
    ## for boundary
    bcfaces = [1]
    # bcfaces = Int64.(bfaces)
    T_all = exported["operators"]["T_all"]
    N_all = Int64.(exported["G"]["faces"]["neighbors"])
    isboundary = (N_all[bcfaces,1].==0) .| (N_all[bcfaces,2].==0)
    @assert all(isboundary)
    bccells = N_all[bcfaces,1] + N_all[bcfaces,2]
    T_hf   = T_all[bcfaces]
    bcvalue = ones(size(bccells))
    bcvaluephi = ones(size(bccells)).*0.0

    domain = exported_model_to_domain(exported, bc = bccells, b_T_hf = T_hf)  
    G = exported["G"]    
    model = SimulationModel(domain, sys, context = DefaultContext())
    parameters = setup_parameters(model)
    parameters[:boundary_currents] = (:BCCharge, :BCMass)

    # State is dict with pressure in each cell
    phi0 = 1.0
    C0 = 1.
    T0 = 1.
    D = 1.
    σ = exported["EffectiveElectricalConductivity"][1].*1000
    λ = exported["thermalConductivity"][1]

    S = model.secondary_variables
    S[:BoundaryPhi] = BoundaryPotential{Phi}()
    S[:BoundaryC] = BoundaryPotential{Phi}()
    S[:BoundaryT] = BoundaryPotential{T}()

    S[:BCCharge] = BoundaryCurrent{ChargeAcc}(bccells.+9)
    S[:BCMass] = BoundaryCurrent{MassAcc}(bccells.+9)
    S[:BCEnergy] = BoundaryCurrent{EnergyAcc}(bccells.+9)

    phi0 = 0.
    init = Dict(
        :Phi                    => phi0,
        :C                      => C0,
        :T                      => T0,
        :Conductivity           => σ,
        :Diffusivity            => D,
        :ThermalConductivity    => λ,
        :BoundaryPhi            => bcvaluephi, 
        :BoundaryC              => bcvalue, 
        :BoundaryT              => bcvalue,
        :BCCharge               => -bcvalue.*9.4575,
        :BCMass                 => bcvalue,
        :BCEnergy               => bcvalue,
        )

    state0 = setup_state(model, init)

    sim = Simulator(model, state0=state0, parameters=parameters)
    return sim, G, state0
end

function test_ac()
    name="model1d"
    fn = string(dirname(pathof(Terv)), "/../data/models/", name, ".mat")
    exported_all = MAT.matread(fn)
    exported = exported_all["model"]["NegativeElectrode"]["CurrentCollector"];
    # sys = ECComponent()
    # sys = ACMaterial();
    #sys = Grafite()
    sys = CurrentCollector()
    (sim, G, state0) = make_system(exported,sys)
    timesteps = diff(LinRange(0, 10, 10)[2:end])
     
    cfg = simulator_config(sim)
    cfg[:linear_solver] = nothing
    states = simulate(sim, timesteps, config = cfg)
    stateref = exported_all["states"]
    return states, G, state0, stateref
end


states, G, state0, stateref = test_ac();

# f= plot_interactive(G, states);
phi_ref = stateref[10]["NegativeElectrode"]["CurrentCollector"]["phi"]
j_ref = stateref[10]["NegativeElectrode"]["CurrentCollector"]["j"]
x = G["cells"]["centroids"]
xf= G["faces"]["centroids"][end]
xfi= G["faces"]["centroids"][2:end-1]
#state0=states[1]
p1 = Plots.plot(x,state0[:Phi];title="Phi")
Plots.plot!(p1,x,phi_ref;linecolor="red")
p2 = Plots.plot(xfi,states[1].TPkGrad_Phi[1:2:end-1];title="Flux")
#p2 = Plots.plot([xf[end]],[state0[:BCCharge][1]];title="Flux")
#Plots.plot!(p2,xfi,j_ref;linecolor="red")
p=plot(p1, p2, layout = (1, 2), legend = false)
Plots.plot!(p1,x,states[end].Phi)
Plots.plot!(p2,xfi,states[end].TPkGrad_Phi[1:2:end-1])
display(plot!(p1, p2, layout = (1, 2), legend = false))
##
for (n,state) in enumerate(states)
    println(n)
    Plots.plot!(p1,x,states[n].Phi)
    Plots.plot!(p2,xfi,states[n].TPkGrad_Phi[1:2:end-1])
    display(plot!(p1, p2, layout = (1, 2), legend = false))
end
##

x = G["cells"]["centroids"]
state0=states[1]
p1 = Plots.plot(x,state0.Phi;title="Phi")
p2 = Plots.plot(x,state0.C;title="C")
p=plot(p1, p2, layout = (1, 2), legend = false)
for (n,state) in enumerate(states)
    println(n)
    Plots.plot!(p1,x,states[n].Phi)
    Plots.plot!(p2,x,states[n].C)
    display(plot!(p1, p2, layout = (1, 2), legend = false))
end
##
x=1:4
for a in x
    println(a)
end