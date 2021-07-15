struct Executor{O, I, M<:ComputeType, F, Fi, Fo}
    ins::ChannelArray{I}
    outs::ChannelArray{O}
    f::F
    fi::Fi
    fo::Fo
    mode::M
    tasks::Vector{RemoteTask}
end

Base.eltype(::Executor{O}) where O = O

do_take!(take!, chn) = take!(chn)
do_put!(put!, chn, r) = put!(chn, r)

Executor(f, mode=Thread(3); do_take! = do_take!, do_put! = do_put!, csize=8, in_ctype=Any, out_ctype=Any) = Executor(f, do_take!, do_put!, mode; csize, in_ctype, out_ctype)

function Executor(f, fi, fo, mode; csize=8, in_ctype=Any, out_ctype=Any)
    indices = collect(ids(mode))
    ins = ChannelArray{in_ctype}(indices, csize)
    outs = ChannelArray{out_ctype}(indices, csize)
    tasks = build_execs(f, ins, outs, mode; do_take! = fi, do_put! = fo)
    Executor(ins, outs, f, fi, fo, mode, tasks)
end

function build_execs(f, ins, outs, mode; do_take! = do_take!, do_put! = do_put!)
    @assert length(ins) == length(outs)
    tasks = Vector{RemoteTask}(undef, length(ins))
    build_execs!(tasks, f, ins, outs, mode; do_take!, do_put!)
    return tasks
end

build_execs!(exe::Executor) = build_execs!(exe.tasks, exe.f, exe.ins, exe.outs, exe.mode; do_take! = exe.fi, do_put! = exe.fo)

function build_execs!(tasks, f, ins, outs, mode; do_take! = do_take!, do_put! = do_put!)
    for i = 1:length(tasks)
        tasks[i] = build_exec(f, ins[i], outs[i], mode; do_take!, do_put!)
    end
    return tasks
end

function build_exec(f, in::RemoteChannel, out::RemoteChannel, mode; do_take! = do_take!, do_put! = do_put!)
    thread = !(mode isa Async)
    @assert in.where == out.where
    return RemoteTask(in.where, remoteref_id(in), remoteref_id(out)) do irrid, orrid
        t = let ic = channel_from_id(irrid), oc = channel_from_id(orrid)
            StopableTask(thread) do
                thrdid = Threads.threadid()
                @debuginfo thrdid
                local v = nothing
                while !should_stop()
                    v = do_take!(stopable_take!, ic)
                    (iserror(v) || should_stop()) && break
                    r = f(unwrap(v))
                    should_stop() && break
                    iserror(do_put!(stopable_put!, oc, r)) && break
                end
                close(oc)
                return v
            end
        end
        return t
    end
end

function start!(exe::Executor)
    foreach(schedule, exe.tasks)
end

function stop!(exe::Executor)
    foreach(stop!, exe.tasks)
    close(exe.outs)
    return
end

function reset!(exe::Executor)
    stop!(exe)
    reopen!(exe.outs)
    build_execs!(exe)
    return exe
end

isfinished(exe::Executor) = istaskdone(exe) && !isopen(exe.outs)

Base.istaskdone(exe::Executor) = all(isfinished, exe.tasks)
