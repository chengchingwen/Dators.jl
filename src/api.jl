import Base

function Base.iterate(d::AbstractDator)
    isfinished(d) && restart!(d)
    return iterate(d, nothing)
end

function Base.iterate(d::AbstractDator, state)
    t = try
        map(c->safe_take!(c), Tuple(d.dsts))
    catch e
        reset!(d)
        if isa(e, InvalidStateException) && e.state === :closed
            return nothing
        else
            rethrow()
        end
    end
    return (t, nothing)
end
