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

batch(d, n, drop_last=true) = batch(collect, d, n, drop_last)
function batch(f, d::AbstractDator, n, drop_last=true)
    function do_batch_take!(take!, c)
        v = ntuple(_->take!(c), n)
        vn = count(!isnothing, v)
        if iszero(vn)
            return
        elseif vn != n && !drop_last
            dont_stop!()
            return filter(!isnothing, v)
        else
            return v
        end
    end
    n_out = length(d.dsts)

    return Dator(f, n_out, d; do_take! = do_batch_take!,
                 compute_type=d.mode,
                 src_connect_type=Parallel(),
                 dst_connect_type=Parallel())
end
