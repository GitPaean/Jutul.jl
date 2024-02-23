initialize_io(::Nothing) = nothing

function initialize_io(path)
    @assert isdir(path) "$path must be a valid directory for output."
end

function retrieve_output!(sim, states, reports, config, n)
    retrieve_output!(states, reports, config, n)
end

function retrieve_output!(states, reports, config, n)
    pth = config[:output_path]
    read_reports = config[:output_reports]
    read_states = config[:output_states]
    if !isnothing(pth) && n > 0 && (read_reports || read_states)
        @debug "Reading $n states from $pth..."
        @assert isempty(states)
        states, reports = read_results(
            pth,
            read_reports = read_reports,
            read_states = read_states,
            states = states,
            verbose = config[:info_level] >= 0,
            range = 1:n
            )
    end
    return (states, reports)
end

function get_output_state(sim::JutulSimulator)
    get_output_state(sim.storage, sim.model)
end

function store_output!(states, reports, step, sim, config, report)
    mem_out = config[:output_states]
    path = config[:output_path]
    file_out = !isnothing(path)
    # We always keep reports in memory since they are used for timestepping logic
    push!(reports, report)
    t_out = @elapsed if mem_out || file_out
        @tic "output state" state = get_output_state(sim)
        @tic "write" if file_out
            write_result_jld2(path, state, report, step)
            for i in 1:(step-config[:in_memory_reports])
                # Only keep the last N time-step reports in memory. These
                # will be read back before output anyway.
                reports[i] = missing
            end
        elseif mem_out
            push!(states, state)
        end
    end
    report[:output_time] = t_out
end

function write_result_jld2(path, state, report, step)
    step_path = joinpath(path, "jutul_$step.jld2")
    @debug "Writing to $step_path"
    jldopen(step_path, "w") do file
        file["state"] = state
        file["report"] = report
        file["step"] = step
    end
end