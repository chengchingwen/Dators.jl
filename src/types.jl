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

function create_channel(mode::ComputeType; csize=16, ctype=Any)
    return [RemoteChannel(()->Channel{ctype}(csize), id)
            for id in ids(mode)]
end

function create_channel(n::Integer, pid::Integer=myid(); csize=16, ctype=Any)
    return [RemoteChannel(()->Channel{ctype}(csize), pid)
            for _ in 1:n]
end
