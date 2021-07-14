using Distributed: call_on_owner, lookup_ref
using ResultTypes: iserror, unwrap

function put_buffered_result(c::Channel{T}, v)::Result{T, InvalidStateException} where T
    lock(c)
    try
        while length(c.data) == c.sz_max
            Base.check_channel_state(c)
            wait(c.cond_put)
        end

        push!(c.data, v)
        # notify all, since some of the waiters may be on a "fetch" call.
        notify(c.cond_take, nothing, true, false)
    catch e
        if e isa InvalidStateException
            return e
        else
            rethrow(e)
        end
    finally
        unlock(c)
    end
    return v
end

function put_unbuffered_result(c::Channel{T}, v)::Result{T, InvalidStateException} where T
    lock(c)
    taker = try
        while isempty(c.cond_take.waitq)
            Base.check_channel_state(c)
            notify(c.cond_wait)
            wait(c.cond_put)
        end
        # unfair scheduled version of: notify(c.cond_take, v, false, false); yield()
        popfirst!(c.cond_take.waitq)
    catch e
        if e isa InvalidStateException
            return e
        else
            rethrow(e)
        end
    finally
        unlock(c)
    end
    schedule(taker, v)
    yield()  # immediately give taker a chance to run, but don't block the current task
    return v
end

function check_channel_state_result(c::Channel)::Result{Nothing, InvalidStateException} where T
    if !isopen(c)
        excp = c.excp
        if excp isa Bool
            @show excp
        end
        excp !== nothing && return excp
        return Base.closed_exception()
    end
    return
end

function put_result!(c::Channel{T}, v)::Result{T, InvalidStateException} where T
    s = unwrap(check_channel_state_result(c))
    !isnothing(s) && return s
    v = convert(T, v)
    if v isa Bool
        @show v
    end
    return Base.isbuffered(c) ? put_buffered_result(c, v) : put_unbuffered_result(c, v)
end

function fetch_result(c::Channel{T})::Result{T, InvalidStateException} where T
    Base.isbuffered(c) ? fetch_buffered_result(c) : Base.fetch_unbuffered(c)
end

function fetch_buffered_result(c::Channel)::Result{T, InvalidStateException} where T
    lock(c)
    try
        while isempty(c.data)
            Base.check_channel_state(c)
            wait(c.cond_take)
        end
        return c.data[1]
    catch e
        if e isa InvalidStateException
            return e
        else
            rethrow(e)
        end
    finally
        unlock(c)
    end
end

function take_result!(c::Channel{T})::Result{T, InvalidStateException} where T
    return Base.isbuffered(c) ? take_buffered_result(c) : take_unbuffered_result(c)
end

function take_buffered_result(c::Channel{T})::Result{T, InvalidStateException} where T
    lock(c)
    try
        while isempty(c.data)
            Base.check_channel_state(c)
            wait(c.cond_take)
        end
        v = popfirst!(c.data)
        notify(c.cond_put, nothing, false, false) # notify only one, since only one slot has become available for a put!.
        return v
    catch e
        if e isa InvalidStateException
            return e
        else
            rethrow(e)
        end
    finally
        unlock(c)
    end
end

function take_unbuffered_result(c::Channel{T})::Result{T, InvalidStateException} where T
    lock(c)
    try
        Base.check_channel_state(c)
        notify(c.cond_put, nothing, false, false)
        return wait(c.cond_take)::T
    catch e
        if e isa InvalidStateException
            return e
        else
            rethrow(e)
        end
    finally
        unlock(c)
    end
end

function take_result_ref(rid, caller, args...)
    rv = lookup_ref(rid)
    synctake = false
    if myid() != caller && rv.synctake !== nothing
        # special handling for local put! / remote take! on unbuffered channel
        # github issue #29932
        synctake = true
        lock(rv.synctake)
    end

    v = try
        take_result!(rv, args...)
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

take_result!(rv::Distributed.RemoteValue, args...) = take_result!(rv.c, args...)
take_result!(rr::RemoteChannel, args...) = @thread1_do call_on_owner(take_result_ref, rr, myid(), args...)::Result{eltype(rr), InvalidStateException}


put_result!(rv::Distributed.RemoteValue, args...) = put_result!(rv.c, args...)
function put_result_ref(rid, caller, args...)
    rv = lookup_ref(rid)
    v = put_result!(rv, args...)
    if myid() == caller && rv.synctake !== nothing
        lock(rv.synctake)
        unlock(rv.synctake)
    end
    return v
end

put_result!(rr::RemoteChannel, args...) = @thread1_do call_on_owner(put_result_ref, rr, myid(), args...)::Result{eltype(rr), InvalidStateException}

fetch_result_ref(rid, args...) = fetch_result(lookup_ref(rid).c, args...)
fetch_result(r::RemoteChannel, args...) = @thread1_do call_on_owner(fetch_result_ref, r, args...)::Result{eltype(r), InvalidStateException}

function wait_result_ref(rid, caller, args...)
    v = fetch_result_ref(rid, args...)
    if isa(v, RemoteException)
        if myid() == caller
            throw(v)
        else
            return v
        end
    end
    if iserror(v)
        return v
    else
        return
    end
end

wait_result(r::RemoteChannel, args...) = @thread1_do call_on_owner(wait_result_ref, r, myid(), args...)::Result{nothing, InvalidStateException}
