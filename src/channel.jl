#bypass julia issue #33972
function _take_ref(rid, caller, args...)
  rv = Distributed.lookup_ref(rid)
    synctake = false
    if myid() != caller && rv.synctake !== nothing
        # special handling for local put! / remote take! on unbuffered channel
        # github issue #29932
        synctake = true
        lock(rv.synctake)
    end

  v = try
    take!(rv, args...)
  catch e
    if synctake
      unlock(rv.synctake)
    end
    rethrow(e)
  end

  isa(v, RemoteException) && (myid() == caller) && throw(v)

    if synctake
        return Distributed.SyncTake(v, rv)
    else
        return v
    end
end

_take!(rr::RemoteChannel, args...) = Distributed.call_on_owner(_take_ref, rr, myid(), args...)::eltype(rr)

safe_take!(rr::RemoteChannel, args...) = _take!(rr, args...)
safe_take!(c::Channel) = take!(c)

isfull(c::Channel) = Base.n_avail(c) >= c.sz_max
isfull(rc::RemoteChannel) = remote_eval(remotecall_fetch, isfull, channel_from_id, rc)

stop!(rc::RemoteChannel) = remote_eval(remote_do, stop!, channel_from_id, rc)
function stop!(c::Channel)
    excp = InvalidStateException("Task should stop", :stop)
    lock(c)
    try
        Base.notify_error(c.cond_take, excp)
        Base.notify_error(c.cond_take, excp)
        Base.notify_error(c.cond_wait, excp)
        Base.notify_error(c.cond_put, excp)
    finally
        unlock(c)
    end
    return
end

function stopable_put!(chn, v)
    should_stop() && return
    if !isopen(chn)
        task_local_storage(:should_stop, true)
        return
    end

    put!(chn, v)
    return v
end

function stopable_take!(chn)
    should_stop() && return
    if isfinished(chn)
        task_local_storage(:should_stop, true)
        return
    end
    
    r = safe_take!(chn)
    return r
end

function putback!(c::Channel{T}, v) where T
    Base.check_channel_state(c)
    v = convert(T, v)
    return Base.isbuffered(c) ? putback_buffered!(c, v) :
        error("cannot put value back to unbuffered channel")
end

function putback_buffered!(c::Channel{T}, v) where T
    lock(c)
    try
        while length(c.data) == c.sz_max
            Base.check_channel_state(c)
            wait(c.cond_put)
        end
        pushfirst!(c.data, v)
        # notify all, since some of the waiters may be on a "fetch" call.
        notify(c.cond_take, nothing, true, false)
    finally
        unlock(c)
    end
    return v
end

cleanup!(rc::RemoteChannel) = remote_eval(remote_do, cleanup!, channel_from_id, rc)
function cleanup!(c::Channel)
    lock(c)
    try
        if !isempty(c.data)
            empty!(c.data)
            notify(c.cond_put, nothing, true, false)
        end
    finally
        unlock(c)
    end
    return
end

reopen(rc::RemoteChannel) = remote_eval(remote_do, reopen, channel_from_id, rc)
function reopen(c::Channel)
    lock(c)
    try
        c.state = :open
        c.excp = nothing
    finally
        unlock(c)
    end
end

isfinished(rc::RemoteChannel) = remote_eval(remotecall_fetch, isfinished, channel_from_id, rc)
isfinished(c::Channel) = !isopen(c) && isempty(c)
