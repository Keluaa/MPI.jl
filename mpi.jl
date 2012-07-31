type Comm
    fcomm::Int32

    function Comm(f::Int32)
        c = new(f)
        finalizer(c, free)
        c
    end
end

convert(::Type{Comm},  x::Int32) = Comm(x)
convert(::Type{Int32}, x::Comm) = Int32(x.fcomm)

typealias MpiDense Union(Float32, Float64, Complex64, Complex128, Bool, Char,
                         Int8, Uint8, Int16, Uint16, Int32, Uint32, Int64,
                         Uint64, Int128, Uint128)

takebuf_array(s::IOStream) =
    ccall(:jl_takebuf_array, Vector{Uint8}, (Ptr{Void},), s.ios)

function free(c::Comm)
    ierr = Array(Int32, 1)
    ccall(MPI_COMM_FREE, Void, (Ptr{Int32},Ptr{Int32},), &c.fcomm, ierr)
    if ierr[1] != MPI_SUCCESS error("MPI_COMM_FREE: error $(ierr[1])") end
end


function init()
    ierr = Array(Int32, 1)
    ccall(MPI_INIT, Void, (Ptr{Int32},), ierr)
    if ierr[1] != MPI_SUCCESS error("MPI_INIT: error $(ierr[1])") end
end

function rank(c::Comm)
    ierr = Array(Int32, 1)
    r = Array(Int32, 1)
    ccall(MPI_COMM_RANK, Void, (Ptr{Int32}, Ptr{Int32}, Ptr{Int32},),
        &c.fcomm, r, ierr)
    if ierr[1] != MPI_SUCCESS error("MPI_COMM_RANK: error $(ierr[1])") end
    r[1]
end

function size(c::Comm)
    ierr = Array(Int32, 1)
    s = Array(Int32, 1)
    ccall(MPI_COMM_SIZE, Void, (Ptr{Int32}, Ptr{Int32}, Ptr{Int32},),
        &c.fcomm, s, ierr)
    if ierr[1] != MPI_SUCCESS error("MPI_COMM_SIZE: error $(ierr[1])") end
    s[1]
end

function barrier(c::Comm)
    ierr = Array(Int32, 1)
    ccall(MPI_BARRIER, Void, (Ptr{Int32},Ptr{Int32},), &c.fcomm, ierr)
    if ierr[1] != MPI_SUCCESS error("MPI_BARRIER: error $(ierr[1])") end
end

function bcast!{T<:MpiDense}(A::Union(Ptr{T},Array{T}), count::Integer,
                             root::Integer, c::Comm)
    ierr = Array(Int32, 1)

    n = count * sizeof(T)

    ccall(MPI_BCAST, Void,
          (Ptr{T}, Ptr{Int32}, Ptr{Int32},  Ptr{Int32}, Ptr{Int32},
          Ptr{Int32},),
          A, &n, &MPI_BYTE, &root, &c.fcomm, ierr)

    if ierr[1] != MPI_SUCCESS error("MPI_BCAST: error $(ierr[1])") end
    A
end

function bcast!{T<:MpiDense}(A::Array{T}, root::Integer, c::Comm)
    bcast!(A, numel(A), root, c)
end

function bcast(A, root::Integer, c::Comm)
    ierr = Array(Int32, 1)
    len  = Array(Int32, 1)

    if rank(c) == root
        s = memio()
        serialize(s, A)
        buf = takebuf_array(s)
        len[1] = numel(buf)
    end

    ccall(MPI_BCAST, Void,
          (Ptr{Int32}, Ptr{Int32}, Ptr{Int32},  Ptr{Int32}, Ptr{Int32},
          Ptr{Int32},),
          len, &sizeof(Int32), &MPI_BYTE, &root, &c.fcomm, ierr)

    if ierr[1] != MPI_SUCCESS error("MPI_BCAST: error $(ierr[1])") end

    if rank(c) != root
        buf = Array(Uint8, len[1])
    end

    ccall(MPI_BCAST, Void,
          (Ptr{Uint8}, Ptr{Int32}, Ptr{Int32},  Ptr{Int32}, Ptr{Int32},
          Ptr{Int32},),
          buf, len, &MPI_BYTE, &root, &c.fcomm, ierr)

    if ierr[1] != MPI_SUCCESS error("MPI_BCAST: error $(ierr[1])") end

    if rank(c) != root
        s = memio()
        write(s, buf)
        seek(s, 0)
        Af = deserialize(s)
        if isa(Af, Function)
            Af()
        else
            Af
        end
    else
        A
    end
end

function finalize()
    ierr = Array(Int32, 1)
    ccall(MPI_FINALIZE, Void, (Ptr{Int32},), ierr)
    if ierr[1] != MPI_SUCCESS error("MPI_FINALIZE: error $(ierr[1])") end
end

const COMM_WORLD = Comm(MPI_COMM_WORLD)
