abstract type PMode end
abstract type Parallel <: PMode end

struct Async <: PMode
  n::Int
end

struct Thread <: PMode
  n::Int
end

struct Process <: Parallel
  n::Int
end

struct ProcessWithIDs <: Parallel
  ids::Vector{Int}
end

num(mode::Async) = mode.n
num(mode::Thread) = mode.n
num(mode::Process) = mode.n
num(mode::ProcessWithIDs) = length(mode.ids)

ids(mode::Async) = 1:mode.n
ids(mode::Thread) = 1:mode.n
ids(mode::Process) = 1:mode.n
ids(mode::ProcessWithIDs) = mode.ids

const ChannelLike{T} = Union{Channel{T}, Distributed.RemoteChannel{Channel{T}}}

