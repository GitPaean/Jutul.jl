export convert_to_immutable_storage, convert_to_mutable_storage, gravity_constant, report_stats, print_stats

const gravity_constant = 9.80665

function convert_to_immutable_storage(dct::AbstractDict)
    for (key, value) in dct
        dct[key] = convert_to_immutable_storage(value)
    end
    return (; (Symbol(key) => value for (key, value) in dct)...)
end

function convert_to_immutable_storage(v::Any)
    # Silently do nothing
    return v
end

function convert_to_mutable_storage(v::NamedTuple)
    D = Dict{Symbol, Any}()
    for k in keys(v)
        D[k] = convert_to_mutable_storage(v[k])
    end
    return D
end

function convert_to_mutable_storage(v::Any)
    # Silently do nothing
    return v
end

function as_cell_major_matrix(v, n, m, model::SimulationModel, offset = 0)
    transp = !is_cell_major(matrix_layout(model.context))
    get_matrix_view(v, n, m, transp, offset)
end

function get_matrix_view(v0, n, m, transp = false, offset = 0)
    if size(v0, 2) == 1
        r_l = view(v0, (offset+1):(offset + n*m))
        if transp
            v = reshape(r_l, m, n)'
        else
            v = reshape(r_l, n, m)
        end
    else
        v = view(v0, (offset+1):(offset+n), :)
        if transp
            v = v'
        end
    end
    return v
end


function check_increment(dx, pvar, key)
    if any(!isfinite, dx)
        bad = findall(isfinite.(dx) .== false)
        n_bad = length(bad)
        n = min(10, length(bad))
        bad = bad[1:n]
        @warn "$key: $n_bad non-finite values found. Indices: (limited to 10) $bad"
    end
end

# function get_row_view(v::AbstractVector, n, m, row, transp = false, offset = 0)
#     v = get_matrix_view(v, n, m, transp, offset)
#     view(v, row, :)
# end

function get_convergence_table(errors::AbstractDict, info_level)
    # Already a dict
    conv_table_fn(errors, true, info_level)
end

function get_convergence_table(errors, info_level)
    d = OrderedDict()
    d[:Base] = errors
    conv_table_fn(d, false, info_level)
end

function conv_table_fn(model_errors, has_models = false, info_level = 3)
    # Info level 1: Function should never be called
    # Info level 2:
    # Info level 3: Just print the non-converged parts?
    # Info level 4+: Full print
    if info_level == 1
        return
    end
    count_crit = 0
    count_ok = 0
    worst_val = 0.0
    worst_tol = 0.0
    worst_name = ""
    print_converged = info_level > 3
    header = ["Equation", "Type", "Name", "‖R‖", "ϵ"]
    alignment = [:l, :l, :l, :r, :r]
    if has_models
        # Make the code easier to have for both multimodel and single model case.
        header = ["Model", header...]
        alignment = [:l, alignment...]
    end
    tbl = []
    tols = Vector{Float64}()
    body_hlines = Vector{Int64}()
    pos = 1
    # Loop over models
    for (model, equations) in model_errors
        # Loop over equations 
        for (mix, eq) in enumerate(equations)
            criterions = eq.criterions
            tolerances = eq.tolerances
            eq_touched = false
            for crit in keys(criterions)
                C = criterions[crit]
                local_errors = C.errors
                local_names = C.names
                tol = tolerances[crit]
                touched = false
                for (i, e) in enumerate(Array(local_errors))
                    touch = print_converged || e > tol
                    if touch && !touched
                        nm = eq.name
                        T = crit
                        tt = tol
                    else
                        nm = ""
                        T = ""
                        tt = ""
                    end
                    touched = touch

                    if touch
                        nm2 = local_names[i]
                        if has_models
                            if eq_touched
                                m = ""
                            else
                                m = String(model)
                            end
                            t = [m nm T nm2 e tt]
                        else
                            t = [nm T nm2 e tt]
                        end
                        push!(tbl, t)
                        push!(tols, tol)
                        pos += 1
                        eq_touched = true
                    end
                    count_crit += 1
                    count_ok += e <= tol
                    e_scale = e/tol
                    if e_scale > worst_val
                        worst_val = e_scale
                        worst_tol = tol
                        if has_models
                            mstr = " from model "*String(model)
                        else
                            mstr = ""
                        end
                        worst_name = "$(eq.name)$mstr ($(local_names[i]))"
                    end
                end
                push!(body_hlines, pos-1)
            end
        end
    end
    tbl = vcat(tbl...)
    if size(tbl, 1) > 0 && info_level > 2
        m_offset = Int64(has_models)
        rpos = (4 + m_offset)
        nearly_factor = 10
        function not_converged(data, i, j)
            if j == rpos
                d = data[i, j]
                t = tols[i]
                return d > t && d > 10*t
            else
                return false
            end
        end
        h1 = Highlighter(f = not_converged,
                         crayon = crayon"red" )
    
        function nearly_converged(data, i, j)
            if j == rpos
                d = data[i, j]
                t = tols[i]
                return d > t && d < nearly_factor*t
            else
                return false
            end
        end
        h2 = Highlighter(f = nearly_converged,
                         crayon = crayon"yellow")
    
        function converged(data, i, j)
            if j == rpos
                return data[i, j] <= tols[i]
            else
                return false
            end
        end
        h3 = Highlighter(f = converged,
                         crayon = crayon"green")
    
        highlighers = (h1, h2, h3)
        
        pretty_table(tbl, header = header,
                                alignment = alignment, 
                                body_hlines = body_hlines,
                                highlighters = highlighers, 
                                formatters = ft_printf("%2.3e", [m_offset + 4]),
                                crop=:none)
    else
        if count_crit == count_ok
            println("✔ $count_ok/$count_crit criteria converged.")
        else
            worst_print = @sprintf "%2.3e (ϵ = %2.3e)" worst_val*worst_tol worst_tol
            println("✘ $count_ok/$count_crit criteria converged.\n\t$worst_name at $worst_print is furthest from convergence.")
        end
    end
end

function report_stats(reports)
    total_time = 0
    # Counts
    total_its = 0
    total_linearizations = 0
    # Various timings
    total_finalize = 0
    total_assembly = 0
    total_linear_update = 0
    total_linear_solve = 0
    total_update = 0
    total_convergence = 0

    total_steps = length(reports)
    total_ministeps = 0
    for outer_rep in reports
        total_time += outer_rep[:total_time]
        for mini_rep in outer_rep[:ministeps]
            total_ministeps += 1
            if haskey(mini_rep, :finalize_time)
                total_finalize += mini_rep[:finalize_time]
            end

            for rep in mini_rep[:steps]
                total_linearizations += 1
                if haskey(rep, :update_time)
                    total_its += 1
                    total_update += rep[:update_time]
                    total_linear_solve += rep[:linear_solve_time]
                end
                total_assembly += rep[:assembly_time]
                total_linear_update += rep[:linear_system_time]
                total_convergence += rep[:convergence_time]
            end
        end
    end
    sum_measured = total_assembly + total_linear_update + total_linear_solve + total_update + total_convergence
    other_time = total_time - sum_measured
    totals = (
                assembly = total_assembly,
                linear_system = total_linear_update,
                linear_solve = total_linear_solve,
                update_time = total_update,
                convergence = total_convergence,
                other = other_time,
                total = total_time
            )
    
    n = total_its
    m = total_linearizations
    linscale = v -> v / max(m, 1)
    itscale = v -> v / max(n, 1)
    each = (
                assembly = linscale(total_assembly),
                linear_system = linscale(total_linear_update),
                linear_solve = itscale(total_linear_solve),
                update_time = itscale(total_update),
                convergence = linscale(total_convergence),
                other = itscale(other_time),
                total = itscale(total_time)
            )
    return (
            newtons = total_its,
            linearizations = total_linearizations,
            steps = total_steps,
            ministeps = total_ministeps,
            time_sum = totals,
            time_each = each
           )
end


function print_stats(reports::AbstractArray)
    stats = report_stats(reports)
    print_stats(stats)
end

function print_stats(stats)
    print_iterations(stats)
    print_timing(stats)
end

function print_iterations(stats)
    flds = [:newtons, :linearizations]
    data = Array{Any}(undef, length(flds), 3)
    nstep = stats.steps
    nmini = stats.ministeps

    for (i, f) in enumerate(flds)
        raw = stats[f]
        data[i, 3] = raw
        data[i, 1] = raw/nstep
        data[i, 2] = raw/nmini
    end
    
    
    pretty_table(data; header = (["Per step", "Per ministep", "Total"], ["#$nstep", "#$nmini", ""]), 
                      row_names = flds,
                      title = "Number of iterations",
                      title_alignment = :c,
                      row_name_column_title = "Type")
end

function print_timing(stats)
    flds = collect(keys(stats.time_each))
    
    n = length(flds)
    hl_last = Highlighter(f = (data, i, j) -> i == n, crayon = Crayon(background = :light_blue))
    
    tscale = 1
    tscale_each = 1
    data = Array{Any}(undef, n, 3)
    tot = stats.time_sum.total*tscale
    for (i, f) in enumerate(flds)
        teach = stats.time_each[f]*tscale_each
        tsum = stats.time_sum[f]*tscale
        data[i, 1] = teach
        data[i, 2] = 100*tsum/tot
        data[i, 3] = tsum
    end
    function pick_unit(t)
        m = maximum(t)
        units = [(24*3600, "Days"), (3600, "Hours"), (60, "Minutes"), (1, "Seconds"), (1e-3, "Milliseconds"), (1e-6, "Microseconds"), (1e-9, "Nanoseconds")]
        for u in units
            if m > u[1]
                return u
            end
        end
    end

    u, s = pick_unit(data[:, 1])
    u_t, s_t = pick_unit(data[:, 3])

    @. data[:, 1] /= u
    @. data[:, 3] /= u_t

    pretty_table(data; header = (["Each", "Total", "Total"], [s, "%", s_t]), 
                      row_names = flds,
                      formatters = (ft_printf("%3.2e", 1), ft_printf("%3.2f", 2:3)),
                      title = "Simulator timing",
                      title_alignment = :c,
                      body_hlines = [n-1],
                      row_name_column_title = "Type")
end

