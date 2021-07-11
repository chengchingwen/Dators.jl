import Distributed: channel_from_id

struct Connect{T, M<:ConnectType}
    froms::Vector{RemoteChannel{Channel{T}}}
    tos::Vector{RemoteChannel{Channel{T}}}
    mode::M
    tasks::Vector{RemoteTask}    
end

Base.eltype(::Connect{T}) where T = T

function Connect(froms::Vector{<:RemoteChannel}, tos::Vector{<:RemoteChannel}, mode=Mixed())
    tasks, mode = build_connection(froms, tos, mode)
    return Connect(froms, tos, mode, tasks)
end

build_connection!(con::Connect) = build_connection!(con.tasks, con.froms, con.tos, con.mode)

build_connection(froms, tos, mode::Mixed) = build_connection!(
    Vector{RemoteTask}(undef, length(froms)*length(tos)),
    froms, tos, mode
)

function build_connection!(tasks, froms, tos, mode::Mixed)
    count = 1
    for from in froms, to in tos
        rt = connect_channel(from, to)
        tasks[count] = rt
        count+=1
    end
    return tasks, mode
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

function build_connection!(tasks, froms, tos, mode::Parallel)
    nt = mode.nt
    overlap = mode.overlap
    count = 1
    if length(froms) <= length(tos)
        shift = 0
        for from in froms
            for j in 1:nt
                to = tos[shift+j]
                rt = connect_channel(from, to)
                tasks[count] = rt
                count+=1
            end
            shift += overlap ? nt-1 : nt
        end
    else
        shift = 0
        for to in tos
            for j in 1:nt
                from = froms[shift+j]
                rt = connect_channel(from, to)
                tasks[count] = rt
                count+=1
            end
            shift += overlap ? nt-1 : nt
        end        
    end
    return tasks, mode
end

function connect_channel(from, to)
    return RemoteTask(from.where, remoteref_id(from)) do rrid
        fc = channel_from_id(rrid)
        tc = to.where == from.where ?
            channel_from_id(remoteref_id(to)) :
            to
        StopableTask(true) do
            task_local_storage(:usr, Threads.threadid())
            while !should_stop()
                v = stopable_take!(fc)
                should_stop() && return
                stopable_put!(tc, v)
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

start!(con::Connect) = foreach(schedule, con.tasks)
function stop!(con::Connect)
    foreach(stop!, con.tasks)
    foreach(stop!, con.froms)
    foreach(stop!, con.tos)
    return
end

function cleanup!(con::Connect)
    foreach(cleanup!, con.froms)
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
