abstract type SrcDator{T} <: AbstractDator{T} end

struct CreateSrc{T, F, M, C <: Connect} <: SrcDator{T}
    f::F
    task::Ref{StopableTask}
    src::Vector{RemoteChannel{Channel{T}}}
    dsts::Vector{RemoteChannel{Channel{T}}}
    mode::M
    con::C
end

Base.eltype(::CreateSrc{T}) where T = T

function CreateSrc(f, t::StopableTask, src::Vector{<:RemoteChannel}, dsts::Vector{<:RemoteChannel}, mode; connect_type=Mixed())
    con = Connect(src, dsts, connect_type)
    return CreateSrc(f, Ref(t), src, dsts, mode, con)
end

function CreateSrc(f, mode=Async(3), pid=myid(); kws...)
    inc = f()
    csize = get(kws, :csize, 8)
    ctype = haskey(kws, :ctype) ? get(kws, :ctype) : eltype(inc)
    src = create_channel(1, pid; csize, ctype)
    dsts = create_channel(mode; csize, ctype)

    t = StopableTask(false) do
        while !should_stop()
            !isopen(inc) && break
            v = stopable_take!(inc)
            (iserror(v) || should_stop()) && break
            stopable_put!(src[1], unwrap(v))
        end
        close(src[1])
    end

    return CreateSrc(f, t, src, dsts, mode; connect_type=get(kws, :connect_type, Mixed()))
end

function start!(s::CreateSrc)
    schedule(s.task[])
    start!(s.con)
end

function stop!(s::CreateSrc)
    stop!(s.task[])
    foreach(stop!, s.src)
    stop!(s.con)
end

cleanup!(s::CreateSrc) = (foreach(cleanup!, s.src); cleanup!(s.con))
function reset!(s::CreateSrc)
    stop!(s)
    cleanup!(s)
    foreach(reopen, s.src)

    inc = s.f()
    src = s.src
    t = StopableTask(false) do
        while !should_stop()
            !isopen(inc) && break
            v = stopable_take!(inc)
            (iserror(v) || should_stop()) && break
            stopable_put!(src[1], unwrap(v))
        end
        close(src[1])
    end
    s.task[] = t
    reset!(s.con)
    return src
end

restart!(s::CreateSrc) = (reset!(s); start!(s))

isfinished(s::CreateSrc) = isfinished(s.task[])
