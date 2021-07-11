import Distributed: AbstractRemoteRef, RRID, test_existing_ref,
    LocalProcess, Worker, MsgHeader, CallMsg, send_msg, schedule_call

mutable struct RemoteTask <: AbstractRemoteRef
    where::Int
    whence::Int
    id::Int

    RemoteTask(w::Int, rrid::RRID) = (r = new(w, rrid.whence, rrid.id); return test_existing_ref(r))
    RemoteTask(t::NTuple{3, Any}) = new(t[1], t[2], t[3])
end

RemoteTask(w::Integer) = RemoteTask(w, RRID())
RemoteTask(w::LocalProcess) = RemoteTask(w.id)
RemoteTask(w::Worker) = RemoteTask(w.id)
function RemoteTask(f::Function, pid::Integer=myid(), args...; kwargs...)
    RemoteTask(f, Distributed.worker_from_id(pid), args...; kwargs...)
end

function RemoteTask(f::Function, w::LocalProcess, args...; kwargs...)
    rrid = RRID()
    schedule_call(rrid, Distributed.local_remotecall_thunk(f, args, kwargs))
    return RemoteTask(w.id, rrid)
end

function RemoteTask(f::Function, w::Worker, args...; kwargs...)
    rrid = RRID()
    send_msg(w, MsgHeader(rrid), CallMsg{:call}(f, args, kwargs))
    return RemoteTask(w.id, rrid)
end

function Distributed.finalize_ref(r::RemoteTask)
    if r.where > 0 # Handle the case of the finalizer having been called manually
        if islocked(Distributed.client_refs)
            # delay finalizer for later, when it's not already locked
            finalizer(finalize_ref, r)
            return nothing
        end
        delete!(Distributed.client_refs, r)
        Distributed.send_del_client(r)
        r.where = 0
    end
    nothing
end

function task_from_id(id)
    rt = lock(Distributed.client_refs) do
        return get(Distributed.PGRP.refs, id, false)
    end
    if rt === false
        throw(ErrorException("Local instance of remote task not found"))
    end
    return rt.c.data[]
end

function remote_eval(remotef, f, idf, r)
    rrid = remoteref_id(r)
    return if r.where == myid()
        f(idf(rrid))
    else
        return remotef(r.where, rrid) do rrid
            f(idf(rrid))
        end
    end
end

Base.schedule(rt::RemoteTask) = remote_do(rt.where, remoteref_id(rt)) do rrid
    schedule(task_from_id(rrid))
end

Base.schedule(rt::RemoteTask, arg; error=false) = remote_do(rt.where, remoteref_id(rt)) do rrid
    schedule(task_from_id(rrid), arg; error)
end

status(rt::RemoteTask) = remote_eval(remotecall_fetch, status, task_from_id, rt)

stop!(rt::RemoteTask) = remote_eval(remote_do, stop!, task_from_id, rt)

isfinished(rt::RemoteTask) = (st = status(rt).state; st == :done || st == :failed)
