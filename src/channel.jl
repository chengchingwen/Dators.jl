stop_channel_exception() = InvalidStateException("Channel should stop.", :stop)

function stopable_put!(chn, v)::Result{eltype(chn), InvalidStateException}
    should_stop() && return stop_channel_exception()
    if @thread1_do !isopen(chn)
        should_stop!()
        return stop_channel_exception()
    end

    r = put_result!(chn, v)
    return r
end

function stopable_take!(chn)::Result{eltype(chn), InvalidStateException}
    should_stop() && return stop_channel_exception()
    if isfinished(chn)
        should_stop!()
        return stop_channel_exception()
    end

    r = take_result!(chn)
    iserror(r) && should_stop!()
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

isfull(c::Channel) = Base.n_avail(c) >= c.sz_max
isfull(rc::RemoteChannel) = remote_eval(remotecall_fetch, isfull, channel_from_id, rc)

stop!(c) = (@thread1_do close(c); nothing)
