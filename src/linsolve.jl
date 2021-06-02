export LinearizedSystem, solve!, AMGSolver, CuSparseSolver, transfer

using SparseArrays, LinearOperators
using IterativeSolvers, Krylov, AlgebraicMultigrid
using CUDA, CUDA.CUSPARSE

struct LinearizedSystem
    jac
    r
    dx
    jac_buffer
    r_buffer
    dx_buffer
end

function LinearizedSystem(sparse_arg, context, layout)
    I, J, V, n, m = sparse_arg
    @assert n == m "Expected square system. Recieved $n (eqs) by $m (variables)."
    r = zeros(n)
    dx = zeros(n)
    jac = sparse(I, J, V, n, m)

    jac_buf, dx_buf, r_buf = V, dx, r

    return LinearizedSystem(jac, r, dx, jac_buf, r_buf, dx_buf)
end

@inline function get_nzval(jac)
    return jac.nzval
end

@inline function get_nzval(jac::AbstractCuSparseMatrix)
    # Why does CUDA and Base differ on capitalization?
    return jac.nzVal
end

function solve!(sys::LinearizedSystem, linsolve = nothing)
    if isnothing(linsolve)
        @assert length(sys.dx) < 50000
        J = sys.jac
        r = sys.r
        sys.dx .= -(J\r)
    else
        solve!(sys, linsolve)
    end
end

function transfer(context::SingleCUDAContext, lsys::LinearizedSystem)
    F = context.float_t
    # Transfer types
    r = CuArray{F}(lsys.r)
    dx = CuArray{F}(lsys.dx)
    jac = CUDA.CUSPARSE.CuSparseMatrixCSC{F}(lsys.jac)
    nzval = get_nzval(jac)
    return LinearizedSystem(jac, r, dx, nzval)
end

# AMG solver (Julia-native)
mutable struct AMGSolver 
    method
    reltol
    preconditioner
    hierarchy
end

function AMGSolver(method = "RugeStuben", reltol = 1e-6)
    AMGSolver(method, reltol, nothing, nothing)
end

function solve!(sys::LinearizedSystem, solver::AMGSolver)
    if isnothing(solver.preconditioner)
        @debug string("Setting up preconditioner ", solver.method)
        if solver.method == "RugeStuben"
            t_amg = @elapsed solver.hierarchy = ruge_stuben(sys.jac)
        else
            t_amg = @elapsed solver.hierarchy = smoothed_aggregation(sys.jac)
        end
        @debug "Set up AMG in $t_amg seconds."
        solver.preconditioner = aspreconditioner(solver.hierarchy)
    end
    t_solve = @elapsed begin 
        gmres!(sys.dx, sys.jac, -sys.r, reltol = solver.reltol, maxiter = 20, 
                                        Pl = solver.preconditioner, verbose = false)
    end
    @debug "Solved linear system to $(solver.reltol) in $t_solve seconds."
end

# CUDA solvers
mutable struct CuSparseSolver
    method
    reltol
    storage
end

function CuSparseSolver(method = "Chol", reltol = 1e-6)
    CuSparseSolver(method, reltol, nothing)
end

function solve!(sys::LinearizedSystem, solver::CuSparseSolver)
    J = sys.jac
    r = sys.r
    n = length(r)

    t_solve = @elapsed begin
        prec = ilu02(J, 'O')
        
        function ldiv!(y, prec, x)
            # Perform inversion of upper and lower part of ILU preconditioner
            copyto!(y, x)
            sv2!('N', 'L', 'N', 1.0, prec, y, 'O')
            sv2!('N', 'U', 'U', 1.0, prec, y, 'O')
            return y
        end
        
        y = similar(r)
        T = eltype(r)
        op = LinearOperator(T, n, n, false, false, x -> ldiv!(y, prec, x))
        
        rt = convert(eltype(r), solver.reltol)
        (x, stats) = dqgmres(J, r, M = op, rtol = rt, verbose = 0, itmax=20)
    end
    @debug "Solved linear system to with message '$(stats.status)' in $t_solve seconds."
    sys.dx .= -x
end

