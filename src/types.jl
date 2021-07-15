abstract type ConnectType end

struct Mixed <: ConnectType end
struct Parallel <: ConnectType
    nt::Int
    overlap::Bool
end

Parallel() = Parallel(0, false)

abstract type ComputeType end
abstract type LocalComputeType <: ComputeType end
abstract type RemoteComputeType <: ComputeType end

struct Async <: LocalComputeType
    n::Int
end

struct Thread <: LocalComputeType
  n::Int
end

struct Process <: RemoteComputeType
  n::Int
end

struct ProcessWithIDs <: RemoteComputeType
  ids::Vector{Int}
end

num(mode::LocalComputeType) = mode.n
num(mode::Process) = mode.n
num(mode::ProcessWithIDs) = length(mode.ids)

ids(mode::LocalComputeType) = (myid() for _ in 1:num(mode))
ids(mode::Process) = (Distributed.nextproc() for _ in 1:num(mode))
ids(mode::ProcessWithIDs) = mode.ids


create_channel(mode::ComputeType; csize=16, ctype=Any) =
    create_channel(ids(mode), csize, ctype)

function create_channel!(buf, mode::ComputeType; csize=16)
    create_channel!(buf, ids(mode), csize)
end
