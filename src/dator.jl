abstract type AbstractDator{T} end

struct Dator{T, S, M <:ComputeType, D <: AbstractDator{S}, E <: Executor{T, S, M}, SC <: Connect{S}, DC <:Connect{T}} <: AbstractDator{T}
    src::D
    dsts::ChannelArray{T}
    mode::M
    src_con::SC
    dst_con::DC
    execs::E
end

Base.eltype(::Dator{T}) where T = T

function Dator(f, src::AbstractDator, dsts::ChannelArray; compute_type=Thread(3), src_connect_type=Mixed(), dst_connect_type=Mixed(), do_take! = do_take!, do_put! = do_put!, csize=8)
    srcs = src.dsts
    execs = Executor(f, do_take!, do_put!, compute_type; csize,
                     in_ctype=eltype(srcs),
                     out_ctype=eltype(dsts))
    src_con = Connect(srcs, execs.ins, src_connect_type)
    dst_con = Connect(execs.outs, dsts, dst_connect_type)
    return Dator(src, dsts, compute_type, src_con, dst_con, execs)
end

function unwrap_type(::Type{<: Result{T, E}}) where {T, E}
    return T
end

unwrap_type(t::Type) = t

function outtype(f, fi, fo, intype)
    it_list = Base.return_types(fi, Tuple{typeof(take_result!), Channel{intype}})
    it = unwrap_type(isempty(it_list) ? Any : first(it_list))
    tt_list = Base.return_types(f, Tuple{it})
    tt = unwrap_type(isempty(tt_list) ? Any : first(tt_list))
    ot_list = Base.return_types(fo, Tuple{typeof(put_result!), Channel{tt}, tt})
    ot = unwrap_type(isempty(ot_list) ? Any : first(ot_list))
    return ot
end

function Dator(f, n::Integer, src::AbstractDator, pid=myid(); kws...)
    fi = get(kws, :do_take!, do_take!)
    fo = get(kws, :do_put!, do_put!)
    ot = outtype(f, fi, fo, eltype(src))
    return Dator{ot}(f, n, src, pid; kws...)
end

function Dator{T}(f, n::Integer, src::AbstractDator, pid=myid(); kws...) where T
    csize = get(kws, :csize, 8)
    dsts = ChannelArray{T}(n, csize, pid)
    return Dator(f, src, dsts; kws...)
end

function propagate(f, d::Dator, do_return=false)
    f(d.src)
    f(d.src_con)
    f(d.execs)
    f(d.dst_con)
    return do_return ? d : nothing
end

start!(d::Dator) = propagate(start!, d)
stop!(d::Dator) = propagate(stop!, d)
function reset!(d::Dator)
    stop!(d)
    reopen!(d.dsts)
    propagate(reset!, d, true)
    return d
end

restart!(d::Dator) = (reset!(d); start!(d))

function isfinished(d::Dator)
    return isfinished(d.src) && isfinished(d.src_con) &&
        isfinished(d.execs) && isfinished(d.dst_con)
end

function Base.istaskdone(d::Dator)
    return istaskdone(d.src) && istaskdone(d.src_con) &&
        istaskdone(d.execs) && istaskdone(d.dst_con)
end

function isstarted(d::Dator)
    return all(t->status(t).state != :init, d.execs.tasks)
end
