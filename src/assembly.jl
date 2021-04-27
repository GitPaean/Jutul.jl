export half_face_flux, half_face_flux!, tp_flux, half_face_flux_kernel

function jacobian!(jac, mass, flux, G)
    
end

function residual!(r, CL, G)
    if isnothing(CL.accumulation)
        for i in eachindex(r)
            r[i] = 0
        end
    else
        for i in eachindex(r)
            r[i] = value(CL.accumulation[i])
        end
    end
    for conn in eachindex(G.conn_data)
        r[conn.self] += value(flux[conn])
    end
end

function half_face_flux(mob, p, G)
    flux = similar(p, 2*G.nfaces)
    half_face_flux!(flux, mob, p, G)
    return flux
end

function half_face_flux!(flux, mob, p, G::TervGrid)
    half_face_flux!(flux, mob, p, G.conn_data)
end

function half_face_flux!(flux, mob, p, fd::Vector{TPFAHalfFaceData{F, I}}) where {F<:AbstractFloat, I<:Integer}
    Threads.@threads for i in eachindex(flux)
        flux[i] = tp_flux(fd[i].self, fd[i].other, fd[i].T, mob, p)
    end
end

function half_face_flux!(flux, mob, p, fd::CuVector{TPFAHalfFaceData{F, I}}) where {F<:AbstractFloat, I<:Integer}
    gpu_bz = 256
    kernel_gpu = half_face_flux_kernel(CUDADevice(), gpu_bz)
    m = length(fd)
    @time begin
        event = kernel_gpu(flux, mob, p, fd, ndrange=m)
        wait(event)
    end
end

@kernel function half_face_flux_kernel(flux, @Const(mob), @Const(p), @Const(fd))
    i = @index(Global)
    @inbounds flux[i] = tp_flux(fd[i].self, fd[i].other, fd[i].T, mob, p)
end

@inline function tp_flux(c_self::I, c_other::I, t_ij, mob::AbstractArray{R}, p::AbstractArray{R}) where {R<:Real, I<:Integer}
    dp = p[c_self] - value(p[c_other])
    if dp > 0
        m = mob[c_self]
    else
        m = value(mob[c_other])
    end
    return m*t_ij*dp
end


