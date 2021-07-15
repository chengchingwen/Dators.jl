import Distributed: channel_from_id

struct Connect{T, M<:ConnectType}
    froms::ChannelArray{T}
    tos::ChannelArray{T}
    mode::M
    tasks::Vector{RemoteTask}
    monitors::IdDict{RemoteChannel{Channel{T}}, RemoteChannel{Channel{Int}}}
end

Base.eltype(::Connect{T}) where T = T

function Connect(froms::ChannelArray, tos::ChannelArray, mode=Mixed())
    tasks, mode, monitors = build_connection(froms, tos, mode)
    return Connect(froms, tos, mode, tasks, monitors)
end

build_connection!(con::Connect) = build_connection!(con.tasks, con.froms, con.tos, con.mode, con.monitors)

build_connection(froms, tos, mode::Mixed) = build_connection!(
    Vector{RemoteTask}(undef, length(froms)*length(tos)),
    froms, tos, mode
)

function build_connection!(tasks, froms, tos, mode::Mixed, monitors=IdDict{RemoteChannel{Channel{eltype(tos)}}, RemoteChannel{Channel{Int}}}())
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
                take!(c)
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

function build_connection!(tasks, froms, tos, mode::Parallel, monitors=IdDict{RemoteChannel{Channel{eltype(tos)}}, RemoteChannel{Channel{Int}}}())
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
                take!(c)
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
                    v = take!(c)
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
                take!(c)
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
    rt = RemoteTask(from.where, remoteref_id(from), remoteref_id(to)) do rrid, torid
        let fc = channel_from_id(rrid), tc = (to.where == from.where ? channel_from_id(torid) : to), to = to
            StopableTask(true) do
                thrdid = Threads.threadid()
                @debuginfo thrdid
                local v = nothing
                while !should_stop()
                    v = stopable_take!(fc)
                    (iserror(v) || should_stop()) && break
                    iserror(stopable_put!(tc, unwrap(v))) && break
                end

                @debuginfo loc=done_loop
                r = @thread1_do remote_do(to.where, remoteref_id(rc)) do id
                    begin
                        m = channel_from_id(id)
                        c = take!(m)
                        c -= 1
                        put!(m, c)
                        if iszero(c)
                            need_close = channel_from_id(torid)
                            close(need_close)
                        end
                        return c
                    end
                end
                @debuginfo loc=done
                return v
            end
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
    foreach(schedule, con.tasks)
end

function stop!(con::Connect)
    foreach(stop!, con.tasks)
    close(con.tos)
    empty!(con.monitors)
    return
end

function reset!(con::Connect)
    stop!(con)
    reopen!(con.tos)
    build_connection!(con)
    return con
end

isfinished(con::Connect) = istaskdone(con) && !isopen(con.tos)

Base.istaskdone(con::Connect) = all(isfinished, con.tasks)
