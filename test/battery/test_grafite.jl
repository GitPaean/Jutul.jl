#=
Electro-Chemical component
A component with electric potential, concentration and temperature
The different potentials are independent (diagonal onsager matrix),
and conductivity, diffusivity is constant.
=#
using Jutul

ENV["JULIA_DEBUG"] = Jutul;


function test_ac()
    name="square_current_collector"
    bcells, T_hf = get_boundary(name)
    one = ones(size(bcells))
    domain, exported = get_cc_grid(name=name, extraout=true, bc=bcells, b_T_hf=T_hf)
    timesteps = LinRange(0, 10, 10)[2:end]
    G = exported["G"]
    
    # sys = ECComponent()
    # sys = ACMaterial();
    sys = Grafite()
    model = SimulationModel(domain, sys, context = DefaultContext())
    parameters = setup_parameters(model)
    parameters[:boundary_currents] = (:BCCharge, :BCMass)

    # State is dict with pressure in each cell
    phi0 = 1.
    C0 = 1.
    T0 = 1.
    D = 1.
    σ = 1.

    S = model.secondary_variables
    S[:BoundaryPhi] = BoundaryPotential{Phi}()
    S[:BoundaryC] = BoundaryPotential{C}()
    S[:BoundaryT] = BoundaryPotential{T}()

    S[:BCCharge] = BoundaryCurrent{Charge}(bcells.+9)
    S[:BCMass] = BoundaryCurrent{Mass}(bcells.+9)
    S[:BCEnergy] = BoundaryCurrent{Energy}(bcells.+9)

    phi0 = 1.
    init = Dict(
        :Phi                    => phi0,
        :C                      => C0,
        :T                      => T0,
        :Conductivity           => σ,
        :Diffusivity            => D,
        :BoundaryPhi            => one, 
        :BoundaryC              => one, 
        :BoundaryT              => one,
        :BCCharge               => one,
        :BCMass                 => one,
        :BCEnergy               => one,
        )

    state0 = setup_state(model, init)

    sim = Simulator(model, state0=state0, parameters=parameters)
    cfg = simulator_config(sim)
    cfg[:linear_solver] = nothing
    cfg[:info_level] = 2
    cfg[:debug_level] = 2
    states, report = simulate(sim, timesteps, config = cfg)
    return states, G
end

states, G = test_ac();

##
f = plot_interactive(G, states);
display(f)