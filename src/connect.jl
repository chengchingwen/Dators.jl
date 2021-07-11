import Distributed: channel_from_id

struct Connect{T, M<:ConnectType}
    froms::Vector{RemoteChannel{Channel{T}}}
    tos::Vector{RemoteChannel{Channel{T}}}
    mode::M
    tasks::Vector{RemoteTask}
    monitors::IdDict{RemoteChannel{Channel{T}}, RemoteChannel{Channel{Int}}}
end

Base.eltype(::Connect{T}) where T = T

function Connect(froms::Vector{<:RemoteChannel}, tos::Vector{<:RemoteChannel}, mode=Mixed())
    tasks, mode, monitors = build_connection(froms, tos, mode)
    return Connect(froms, tos, mode, tasks, monitors)
end

build_connection!(con::Connect) = build_connection!(con.tasks, con.froms, con.tos, con.mode, con.monitors)

build_connection(froms, tos, mode::Mixed) = build_connection!(
    Vector{RemoteTask}(undef, length(froms)*length(tos)),
    froms, tos, mode
)

function build_connection!(tasks, froms, tos, mode::Mixed, monitors=IdDict{eltype(tos), RemoteChannel{Channel{Int}}}())
    n = length(froms)
    for to in tos
        if !haskey(monitors, to)
            rc = RemoteChannel(to.where) do
                c = Channel{Int}(1)
                put!(c, n)
                return c
            end
            monitors[to] = rc
        else
            rc = monitors[to]
            remote_do(rc.where, remoteref_id(rc)) do rrid
                c = channel_from_id(rrid)
                safe_take!(c)
                put!(c, n)
            end
        end
    end

    count = 1
    for from in froms, to in tos
        rt = connect_channel(from, to, monitors)
        tasks[count] = rt
        count+=1
    end
    return tasks, mode, monitors
end

function build_connection(froms, tos, mode::Parallel)
    n = length(froms)
    m = length(tos)
    d, r = n <= m ? divrem(m, n) : divrem(n, m)
    nt = r > 0 ? d+1 : d
    num_task = nt * min(m, n)
    tasks = Vector{RemoteTask}(undef, num_task)
    return build_connection!(
        tasks, froms, tos, Parallel(nt, r>0))
end

function build_connection!(tasks, froms, tos, mode::Parallel, monitors=IdDict{eltype(tos), RemoteChannel{Channel{Int}}}())
    for to in tos
        if !haskey(monitors, to)
            rc = RemoteChannel(to.where) do
                c = Channel{Int}(1)
                put!(c, 0)
                return c
            end
            monitors[to] = rc
        else
            rc = monitors[to]
            remote_do(rc.where, remoteref_id(rc)) do rrid
                c = channel_from_id(rrid)
                safe_take!(c)
                put!(c, 0)
            end
        end
    end

    nt = mode.nt
    overlap = mode.overlap
    count = 1
    if length(froms) <= length(tos)
        shift = 0
        for from in froms
            for j in 1:nt
                to = tos[shift+j]
                rt = connect_channel(from, to, monitors)
                tasks[count] = rt
                count+=1

                rc = monitors[to]
                remote_do(rc.where, remoteref_id(rc)) do rrid
                    c = channel_from_id(rrid)
                    v = safe_take!(c)
                    put!(c, v+1)
                end

            end
            shift += overlap ? nt-1 : nt
        end
    else
        shift = 0
        for to in tos
            rc = monitors[to]
            remote_do(rc.where, remoteref_id(rc)) do rrid
                c = channel_from_id(rrid)
                safe_take!(c)
                put!(c, nt)
            end

            for j in 1:nt
                from = froms[shift+j]
                rt = connect_channel(from, to, monitors)
                tasks[count] = rt
                count+=1
            end
            shift += overlap ? nt-1 : nt
        end        
    end
    return tasks, mode, monitors
end

function connect_channel(from, to, monitors)
    rc = monitors[to]
    rt = RemoteTask(from.where, remoteref_id(from)) do rrid
        fc = channel_from_id(rrid)
        tc = to.where == from.where ?
            channel_from_id(remoteref_id(to)) :
            to
        StopableTask(true) do
            task_local_storage(:usr, Threads.threadid())
            while !should_stop()
                v = stopable_take!(fc)
                should_stop() && break
                stopable_put!(tc, v)
            end

            v = remotecall_fetch(rc.where, remoteref_id(rc)) do id
                c = channel_from_id(id)
                v = safe_take!(c)
                v -= 1
                put!(c, v)
                if iszero(v)
                    close(to)
                end
                return v
            end
            return v
        end
    end
end

wrap_channel(rc::RemoteChannel) = rc
wrap_channel(c::Channel) = RemoteChannel(()->c, myid())

function Connect(froms::Vector, tos::Vector, mode=Mixed())
    rfroms = map(wrap_channel, froms)
    rtos = map(wrap_channel, tos)
    return Connect(rfroms, rtos, mode)
end

function start!(con::Connect)
    foreach(reopen, con.tos)
    foreach(schedule, con.tasks)
end

function stop!(con::Connect)
    foreach(stop!, con.tasks)
    foreach(stop!, con.tos)
    return
end

function cleanup!(con::Connect)
    foreach(cleanup!, con.tos)
    return
end

function reset!(con::Connect)
    stop!(con)
    cleanup!(con)
    build_connection!(con)
    return con
end

isfinished(con::Connect) = all(isfinished, con.tasks)
