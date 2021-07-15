abstract type SrcDator{T} <: AbstractDator{T} end

struct CreateSrc{T, F, M, C <: Connect} <: SrcDator{T}
    f::F
    task::Ref{StopableTask}
    src::ChannelArray{T}
    dsts::ChannelArray{T}
    mode::M
    con::C
end

Base.eltype(::CreateSrc{T}) where T = T

function CreateSrc(f, t::StopableTask, src::ChannelArray, dsts::ChannelArray, mode; connect_type=Mixed())
    con = Connect(src, dsts, connect_type)
    return CreateSrc(f, Ref(t), src, dsts, mode, con)
end

function CreateSrc(f, mode=Async(3), pid=myid(); kws...)
    inc = f()
    csize = get(kws, :csize, 8)
    ctype = haskey(kws, :ctype) ? get(kws, :ctype) : eltype(inc)
    src = ChannelArray{ctype}(1, csize, pid)
    dsts = ChannelArray{ctype}(ids(mode), csize)

    t = let inc = inc
        StopableTask(false) do
            while !should_stop()
                !isopen(inc) && break
                v = stopable_take!(inc)
                (iserror(v) || should_stop()) && break
                stopable_put!(src[1], unwrap(v))
            end
            close(src)
        end
    end
    return CreateSrc(f, t, src, dsts, mode; connect_type=get(kws, :connect_type, Mixed()))
end

function start!(s::CreateSrc)
    schedule(s.task[])
    start!(s.con)
end

function stop!(s::CreateSrc)
    stop!(s.task[])
    stop!(s.con)
    close(s.src)
end

function reset!(s::CreateSrc)
    stop!(s)
    reopen!(s.src)

    s.task[] = let inc = s.f(), src = s.src
        StopableTask(false) do
            while !should_stop()
                !isopen(inc) && break
                v = stopable_take!(inc)
                (iserror(v) || should_stop()) && break
                stopable_put!(src[1], unwrap(v))
            end
            close(src)
        end
    end
    reset!(s.con)
    return s
end

restart!(s::CreateSrc) = (reset!(s); start!(s))

isfinished(s::CreateSrc) = istaskdone(s) && !isopen(s.src) && isfinished(s.con)

Base.istaskdone(s::CreateSrc) = isfinished(s.task[])
