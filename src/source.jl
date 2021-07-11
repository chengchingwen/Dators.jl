abstract type SrcDator{T} end

struct CreateSrc{T, F, M, C <: Connect} <: SrcDator{T}
    f::F
    task::Ref{StopableTask}
    src::Vector{RemoteChannel{T}}
    dsts::Vector{RemoteChannel{T}}
    mode::M
    con::C
end

function CreateSrc(f, t::StopableTask, src::Vector{<:RemoteChannel}, dsts::Vector{<:RemoteChannel}, mode; connect_type=Mixed())
    con = Connect(src, dsts, connect_type)
    return CreateSrc(f, Ref(t), src, dsts, mode, con)
end

function CreateSrc(f, mode=Async(3), pid=myid(); timeout=3, kws...)
    inc = f()
    csize = get(kws, :csize, 8)
    ctype = haskey(kws, :ctype) ? get(kws, :ctype) : eltype(inc)
    src = create_channel(1, pid; csize, ctype)
    dsts = create_channel(mode; csize, ctype)
    
    t = StopableTask(false) do
        task_local_storage(:usr, timeout)
        while !should_stop()
            !isopen(inc) && break
            v = _take_timeout(inc, timeout)
            should_stop() && break
            put!(src[1], v)
        end
        close(src[1])
    end

    return CreateSrc(f, t, src, dsts, mode; connect_type=get(kws, :connect_type, Mixed()))
end

function _take_timeout(chn, timeout)
    @async begin
        sleep(timeout)
        lock(chn)
        try
            if !isempty(chn.cond_take.waitq)
                close(chn)
            end
        finally
            unlock(chn)
        end
    end
    t = @async take!(chn)
    try
        wait(t)
    catch
        task_local_storage()[:should_stop] = true
        return
    end
    return Base.task_result(t)
end

function start!(s::CreateSrc)
    schedule(s.task[])
    start!(s.con)
end

stop!(s::CreateSrc) = (stop!(s.task[]); stop!(s.con))
cleanup!(s::CreateSrc) = cleanup!(s.con)
function reset!(s::CreateSrc)
    stop!(s)
    cleanup!(s)
    
    inc = s.f()
    timeout = s.task[].storage[:usr]
    src = s.src
    t = StopableTask(false) do
        task_local_storage(:usr, timeout)
        while !should_stop()
            !isopen(inc) && break
            v = _take_timeout(inc, timeout)
            should_stop() && break
            put!(src[1], v)
        end
        close(src[1])
    end
    s.task[] = t
    return
end

restart!(s::CreateSrc) = (reset!(s); start!(d))

isfinished(s::CreateSrc) = isfinished(s.task[])
