stop_channel_exception() = InvalidStateException("Channel should stop.", :stop)

function stopable_put!(chn, v)::Result{eltype(chn), InvalidStateException}
    @debuginfo loc=put_check
    should_stop() && return stop_channel_exception()

    @debuginfo loc=pre_put put=$v
    r = put_result!(chn, v)
    @debuginfo loc=post_put put=$r
    return r
end

function stopable_take!(chn)::Result{eltype(chn), InvalidStateException}
    @debuginfo loc=take_check
    should_stop() && return stop_channel_exception()

    @debuginfo loc=pre_take
    r = take_result!(chn)
    @debuginfo loc=post_take take=$r
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

isfinished(rc::RemoteChannel) = remote_eval(remotecall_fetch, isfinished, channel_from_id, rc)
isfinished(c::Channel) = !isopen(c) && isempty(c)

isfull(c::Channel) = Base.n_avail(c) >= c.sz_max
isfull(rc::RemoteChannel) = remote_eval(remotecall_fetch, isfull, channel_from_id, rc)

stop!(c) = (@thread1_do close(c); nothing)
