struct Dator{T, S, M <:ComputeType, E <: Executor{T, S, M}, SC <: Connect{S}, DC <:Connect{T}}
    srcs::Vector{RemoteChannel{Channel{S}}}
    dsts::Vector{RemoteChannel{Channel{T}}}
    mode::M
    src_con::SC
    dst_con::DC
    execs::E
end

function Dator(f, srcs::Vector{<:RemoteChannel}, dsts::Vector{<:RemoteChannel}; compute_type=Thread(3), src_connect_type=Mixed(), dst_connect_type=Mixed(), do_take! = do_take!, do_put! = do_put!, csize=8)
    execs = Executor(f, do_take!, do_put!, compute_type; csize,
                     in_ctype=eltype(eltype(srcs)),
                     out_ctype=eltype(eltype(dsts)))
    src_con = Connect(srcs, execs.ins, src_connect_type)
    dst_con = Connect(execs.outs, dsts, dst_connect_type)
    return Dator(srcs, dsts, compute_type, src_con, dst_con, execs)
end

function Dator(f, n::Integer, srcs::Vector{<:RemoteChannel}, pid=myid(); kws...)
    csize = get(kws, :csize, 8)
    fi = get(kws, :do_take!, do_take!)
    fo = get(kws, :do_put!, do_put!)
    it = Base.return_types(fi, Tuple{typeof(take!), Channel{eltype(eltype(srcs))}})[]
    tt = Base.return_types(f, Tuple{it})[]
    ot = Base.return_types(fo, Tuple{typeof(put!), Channel{Any}, tt})[]
    out_type = haskey(kws, :out_type) ? kws[:out_type] : ot
    dsts = create_channel(n, pid; csize, ctype=out_type)
    return Dator(f, srcs, dsts; kws...)
end

function propagate(f, d::Dator, do_return=false)
    f(d.src_con)
    f(d.execs)
    f(d.dst_con)
    return do_return ? d : nothing
end

start!(d::Dator) = propagate(start!, d)
stop!(d::Dator) = propagate(stop!, d)
clear!(d::Dator) = propagate(clear!, d)
reset!(d::Dator) = (stop!(d); propagate(reset!, d, true))

