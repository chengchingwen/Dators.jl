import Base

function Base.iterate(d::AbstractDator)
    isfinished(d) && restart!(d)
    return iterate(d, nothing)
end

function Base.iterate(d::AbstractDator, state)
    t = map(c->take_result!(c), Tuple(d.dsts))
    if any(iserror, t)
        return nothing
    else
        return (unwrap.(t), nothing)
    end
end

batch(d, n, drop_last=true) = batch(collect, d, n, drop_last)
function batch(f, d::AbstractDator, n, drop_last=true)
    function do_batch_take!(take!, c)::Result{Vector{eltype(c)}, InvalidStateException}
        count = 0
        buf = Vector{eltype(c)}()
        for i = 1:n
            v = take!(c)
            if iserror(v)
                if drop_last
                    should_stop!()
                    return stop_channel_exception()
                else
                    return buf
                end
            else
                push!(buf, unwrap(v))
            end
        end
        return buf
    end
    n_out = length(d.dsts)

    return Dator(f, n_out, d; do_take! = do_batch_take!,
                 compute_type=d.mode,
                 src_connect_type=Parallel(),
                 dst_connect_type=Parallel())
end
