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
    
    put!(chn, v)
    return v
end

function stopable_take!(chn)
    should_stop() && return
    
    r = take!(chn)
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

clear!(rc::RemoteChannel) = remote_eval(remote_do, clear!, channel_from_id, rc)
function clear!(c::Channel)
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
