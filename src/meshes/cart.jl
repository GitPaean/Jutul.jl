struct CartesianMesh <: AbstractTervMesh
    dims   # Tuple of dimensions (x, y, [z])
    deltas # Either a tuple of scalars (uniform grid) or a tuple of vectors (non-uniform grid)
    origin # Coordinate of lower left corner
    function CartesianMesh(dims::Tuple, deltas_or_size::Union{Nothing, Tuple} = nothing; origin = nothing)
        dim = length(dims)
        if isnothing(deltas_or_size)
            deltas_or_size = Tuple(ones(dim))
        end
        if isnothing(origin)
            origin = zeros(dim)
        end
        function generate_deltas(deltas_or_size)
            deltas = Vector(undef, dim)
            for (i, D) = enumerate(deltas_or_size)
                if isa(D, AbstractFloat)
                    # Deltas are actually size of domain in each direction
                    deltas[i] = D/dims[i]
                else
                    # Deltas are the actual cell widths
                    @assert length(D) == dims[i]
                    deltas[i] = D
                end
            end
            return Tuple(deltas)
        end
        @assert length(deltas_or_size) == dim
        deltas = generate_deltas(deltas_or_size)
        return new(dims, deltas, origin)
    end
end

dim(t::CartesianMesh) = length(t.dims)
number_of_cells(t::CartesianMesh) = prod(t.dims)
function number_of_faces(t::CartesianMesh)
    nx, ny, nz = get_3d_dims(t)
    return (nx-1)*ny*nz + (ny-1)*nx*nz + (nz-1)*ny*nx
end

"""
Lower corner for one dimension, without any transforms applied
"""
coord_offset(pos, δ::AbstractFloat) = (pos-1)*δ
coord_offset(pos, δ::AbstractVector) = sum(δ[1:(pos-1)])

"""
Linear index of Cartesian mesh cell
"""
function cell_index(g, pos)
    nx, ny, nz = get_3d_dims(g)
    x, y, z = get_3d_pos(g, pos)
    return (z-1)*nx*ny + (y-1)*nx + x
end

"""
Cell dimensions (as 3 tuple)
"""
function cell_dims(g, pos)
    x, y, z = get_3d_pos(g, pos)
    Δ = g.deltas
    return (get_delta(Δ, x, 1), get_delta(Δ, y, 2), get_delta(Δ, z, 3))
end

function tpfv_geometry(g::CartesianMesh)
    Δ = g.deltas
    d = dim(g)

    nx, ny, nz = get_3d_dims(g)

    # Cell data first - volumes and centroids
    nc = nx*ny*nz
    V = zeros(nc)
    cell_centroids = zeros(d, nc)
    for x in 1:nx
        for y in 1:ny
            for z = 1:nz
                pos = (x, y, z)
                c = cell_index(g, pos)
                cdim  = cell_dims(g, pos)
                V[c] = prod(cdim)

                for i in 1:d
                    cell_centroids[i, c] = coord_offset(pos[i], Δ[i]) + cdim[i]/2 + g.origin[i]
                end
            end
        end
    end

    # Then face data:
    nf = number_of_faces(g)
    N = Matrix{Int}(undef, 2, nf)
    face_areas = Vector{Float64}(undef, nf)
    face_centroids = zeros(d, nf)
    face_normals = zeros(d, nf)

    function add_face!(face_areas, face_normals, face_centroids, x, y, z, D, pos)
        t = (x, y, z)
        index = cell_index(g, t)
        N[1, pos] = index
        N[2, pos] = cell_index(g, (x + (D == 1), y + (D == 2), z + (D == 3)))
        Δ  = cell_dims(g, t)
        # Face area
        A = 1
        for i in setdiff(1:3, D)
            A *= Δ[i]
        end
        face_areas[pos] = A
        face_normals[D, pos] = 1.0

        face_centroids[:, pos] = cell_centroids[:, index]
        # Offset by the grid size
        face_centroids[D, pos] += Δ[D]/2.0
    end
    # Note: The following loops are arranged to reproduce the MRST ordering.
    pos = 1
    # Faces with X-normal > 0
    for z = 1:nz
        for y in 1:ny
            for x in 1:(nx-1)
                add_face!(face_areas, face_normals, face_centroids, x, y, z, 1, pos)
                pos += 1
            end
        end
    end
    # Faces with Y-normal > 0
    for y in 1:(ny-1)
        for z = 1:nz
            for x in 1:nx
                add_face!(face_areas, face_normals, face_centroids, x, y, z, 2, pos)
                pos += 1
            end
        end
    end
    # Faces with Z-normal > 0
    for z = 1:(nz-1)
        for y in 1:ny
            for x in 1:nx
                add_face!(face_areas, face_normals, face_centroids, x, y, z, 3, pos)
                pos += 1
            end
        end
    end

    return TwoPointFiniteVolumeGeometry(N, face_areas, V, face_normals, cell_centroids, face_centroids)
end

function get_3d_dims(g)
    d = length(g.dims)
    if d == 1
        nx = g.dims[1]
        ny = nz = 1
    elseif d == 2
        nx, ny = g.dims
        nz = 1
    else
        @assert d == 3
        nx, ny, nz = g.dims
    end
    return (nx, ny, nz)
end

function get_3d_pos(g, t::Tuple)
    d = length(t)
    if d == 1
        nx = t[1]
        ny = nz = 1
    elseif d == 2
        nx, ny = t
        nz = 1
    else
        @assert d == 3
        nx, ny, nz = t
    end
    return (nx, ny, nz)
end

function get_3d_pos(g, t::Integer)
    error("Not implemented")
end


function get_delta(Δ, index, d)
    if length(Δ) >= d
        δ = Δ[d]
        if isa(δ, AbstractFloat)
            v = δ
        else
            v = δ[index]
        end
    else
        v = 1.0
    end
    return v
end


function triangulate_outer_surface(m::CartesianMesh, is_depth = true)
    pts = []
    tri = []
    cell_ix = []
    face_index = []
    offset = 0
    d = dim(m)
    # nc = number_of_cells(m)
    if d == 2
        nx, ny, = m.dims
        Δ = m.deltas
        for x = 1:nx
            for y = 1:ny
                t = (x, y, 1)
                dx, dy,  = cell_dims(m, t)
                x0 = coord_offset(x, Δ[1])
                y0 = coord_offset(y, Δ[2])

                local_pts = [x0      y0;
                             x0 + dx y0;
                             x0 + dx y0 + dy
                             x0      y0 + dy]
                local_tri = [1 2 3; 3 4 1]
                push!(pts, local_pts)
                push!(tri, local_tri .+ offset)
                push!(cell_ix, repeat([cell_index(m, t)], 4))
                offset += 4
            end
        end
    else
        @assert d == 3

    end
    pts = vcat(pts...)
    tri = vcat(tri...)

    cell_ix = vcat(cell_ix...)
    face_index = vcat(face_index...)

    mapper = (
                Cells = (cell_data) -> cell_data[cell_ix],
                Faces = (face_data) -> face_data[face_index],
                indices = (Cells = cell_ix, Faces = face_index)
              )
    return (pts, tri, mapper)
end