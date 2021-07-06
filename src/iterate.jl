using Distributed

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
    v = take!(rv, args...)
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

Base.take!(rr::RemoteChannel, args...) = _take!(rr, args...)

function Base.iterate(rc::Distributed.RemoteChannel, state=nothing)
  try
    return (take!(rc), nothing)
  catch e
    if isa(e, InvalidStateException) && e.state === :closed
      return nothing
    else
      rethrow()
    end
  end
end

Base.IteratorSize(::Type{<:RemoteChannel}) = Base.SizeUnknown()
