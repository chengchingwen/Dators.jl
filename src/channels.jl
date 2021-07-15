create_channel(n::Integer, pid::Integer=myid(); csize=16, ctype=Any) =
    create_channel(ntuple(_->pid, n); csize, ctype)

function create_channel(ids, csize=16, ctype=Any)
    buf = Vector{RemoteChannel{Channel{ctype}}}(undef, length(ids))
    return create_channel!(buf, ids, csize)
end

function create_channel!(buf::Vector{RemoteChannel{Channel{T}}}, n::Integer, pid::Integer=myid(); csize=16) where T
    create_channel!(buf, ntuple(_->pid, n), csize)
end

function create_channel!(buf::Vector{RemoteChannel{Channel{T}}}, ids, csize) where T
    @thread1_do for (i, id) in enumerate(ids)
        buf[i] = RemoteChannel(()->Channel{T}(csize), id)
    end
    return buf
end

struct ChannelArray{T}
    num::Int
    csize::Int
    chans::Vector{RemoteChannel{Channel{T}}}
end

ChannelArray(num::Int, csize::Int, pid::Int=myid()) = ChannelArray{Any}(num, csize, pid)
ChannelArray{T}(num::Int, csize::Int, pid::Int=myid()) where T = ChannelArray{T}(ntuple(_->pid, num), csize)

ChannelArray(ids, csize) = ChannelArray{Any}(ids, csize)
function ChannelArray{T}(ids, csize) where T
    chans = create_channel(ids, csize, T)
    return ChannelArray{T}(length(ids), csize, chans)
end

function reopen!(ca::ChannelArray)
    ids = map(rc->rc.where, ca.chans)
    close(ca)
    create_channel!(ca.chans, ids, ca.csize)
    return ca
end

Base.close(ca::ChannelArray) = @thread1_do foreach(close, ca.chans)
Base.close(ca::ChannelArray, i) = @thread1_do close(ca[i])
Base.isopen(ca::ChannelArray) = @thread1_do all(isopen, ca.chans)
Base.isopen(ca::ChannelArray, i) = @thread1_do isopen(ca[i])

Base.eltype(::ChannelArray{T}) where T = T
Base.length(ca::ChannelArray) = ca.num
Base.getindex(ca::ChannelArray, args...) = getindex(ca.chans, args...)
Base.iterate(ca::ChannelArray, args...) = iterate(ca.chans, args...)
