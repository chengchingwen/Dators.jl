@enum DStatus Init Run End

struct Dator{R, S, C, F, F0, F1, M0, M}
  mode::PMode
  map_do_pre_f::M0
  do_pre_f::F0
  map_do_f::M
  f::F
  do_post_f::F1
  srcs::S
  input::Ref{C}
  result::Ref{R}
  execs::Vector{E} where E <: Executor
  status::Ref{DStatus}
  cond_start::Union{Threads.Condition, Distributed.Future}
  cond_end::Union{Threads.Condition, Distributed.Future}
end

function create_executors(f, con, dst, mode; map_do_f=map_do_f, do_post_f=do_post_f)
  return map(i->Executor(f, con, dst, typeof(mode), i; map_do_f, do_post_f), ids(mode))
end

function create_executors!(f, execs, con, dst, mode; map_do_f=map_do_f, do_post_f=do_post_f)
  return map!(i->Executor(f, con, dst, typeof(mode), i; map_do_f, do_post_f), execs, ids(mode))
end

do_pre_f(ch, src) = put!(ch, src)
map_do_pre_f(ch, srcs, do_pre_f=do_pre_f) = foreach(Base.Fix1(do_pre_f, ch), srcs)

wait_cond(c::Distributed.Future) = wait(c)
function wait_cond(c::Threads.Condition)
  lock(c)
  try
    wait(c)
  finally
    unlock(c)
  end
end

notify_cond(c::Distributed.Future) = put!(c, true)
function notify_cond(c::Threads.Condition)
  lock(c)
  try
    notify(c)
  finally
    unlock(c)
  end
end

function Dator(f, srcs;
               mode=Async(2),
               csize=2num(mode), ctype=eltype(srcs),
               res_csize=32, res_ctype=Any,
               pid = Distributed.myid(),
               map_do_pre_f=map_do_pre_f,
               do_pre_f=do_pre_f,
               map_do_f=map_do_f,
               do_post_f=do_post_f)
  r = Ref(Init)
  if mode isa Parallel
    cond_start = Distributed.Future(pid)
    cond_end = Distributed.Future(pid)
    chn = Distributed.RemoteChannel(pid) do
      Channel(csize=csize, ctype=ctype) do ch
        wait_cond(cond_start)
        map_do_pre_f(ch, srcs, do_pre_f)
        notify_cond(cond_end)
      end
    end
    dst = Distributed.RemoteChannel(pid) do
      Channel{res_ctype}(res_csize)
    end
  else
    l = ReentrantLock()
    cond_start = Threads.Condition(l)
    cond_end = Threads.Condition(l)
    chn = Channel(csize=csize, ctype=ctype) do ch
      wait_cond(cond_start)
      map_do_pre_f(ch, srcs, do_pre_f)
      notify_cond(cond_end)
    end
    dst = Channel{res_ctype}(res_csize)
  end

  execs = create_executors(f, chn, dst, mode; map_do_f, do_post_f)

  if mode isa Parallel
    final = Distributed.@spawnat pid begin
      wait_cond(cond_end)
      for e in execs
        wait(e)
      end
      close(dst)
      r[] = End
    end
  else
    final = Threads.@spawn begin
      wait_cond(cond_end)
      for e in execs
        wait(e)
      end
      close(dst)
      r[] = End
    end
  end

  return Dator(mode,
               map_do_pre_f, do_pre_f,
               map_do_f, f, do_post_f,
               srcs, Ref(chn), Ref(dst), execs,
               r, cond_start, cond_end)
end

function setfield(d::Dator, key::Symbol, value)
  attr = map(fieldnames(typeof(d))) do name
    name == key ? value : getfield(d, name)
  end
  return Dator(attr...)
end

isstarted(d::Dator) = d.status[] != Init
isstoped(d::Dator) = d.status[] == End
start!(d::Dator) = (notify_cond(d.cond_start); d.status[] = Run)

function reset!(x)
  @warn "type $(typeof(x)) does not support reset, promblem might happen"
  return x
end
reset!(x::Union{AbstractArray, Tuple, NamedTuple, AbstractDict}) = x
function reset!(d::Dator)
  reset!(d.srcs)
  mode = d.mode
  srcs = d.srcs
  ctype = eltype(d.input[])
  res_ctype = eltype(d.result[])
  cond_start = d.cond_start
  cond_end = d.cond_end
  f = d.f
  map_do_pre_f = d.map_do_pre_f
  do_pre_f = d.do_pre_f
  map_do_f = d.map_do_f
  do_post_f = d.do_post_f
  r = d.status
  if d.mode isa Parallel
    csize = Distributed.channel_from_id(remoteref_id(d.input[])).sz_max
    res_csize = Distributed.channel_from_id(remoteref_id(d.result[])).sz_max
    pid = d.cond_end.where
    cond_start.v = nothing
    cond_end.v = nothing
    chn = Distributed.RemoteChannel(pid) do
      Channel(csize=csize, ctype=ctype) do ch
        wait_cond(cond_start)
        map_do_pre_f(ch, srcs, do_pre_f)
        notify_cond(cond_end)
      end
    end
    dst = Distributed.RemoteChannel(pid) do
      Channel{res_ctype}(res_csize)
    end
  else
    csize = d.input[].sz_max
    res_csize = d.result[].sz_max
    chn = Channel(csize=csize, ctype=ctype) do ch
      wait_cond(cond_start)
      map_do_pre_f(ch, srcs, do_pre_f)
      notify_cond(cond_end)
    end
    dst = Channel{res_ctype}(res_csize)
  end

  execs = create_executors!(f, d.execs, chn, dst, mode; map_do_f, do_post_f)

  d.input[] = chn
  d.result[] = dst

  if mode isa Parallel
    final = Distributed.@spawnat pid begin
      wait_cond(cond_end)
      for e in execs
        wait(e)
      end
      close(dst)
      r[] = End
    end
  else
    final = Threads.@spawn begin
      wait_cond(cond_end)
      for e in execs
        wait(e)
      end
      close(dst)
      r[] = End
    end
  end
  r[] = Init
  return d
end


function Base.take!(d::Dator)
  !isstarted(d) && start!(d)
  take!(d.result[])
end

function Base.iterate(d::Dator, state=nothing)
  !isstarted(d) && start!(d)
  iterate(d.result[], state)
end

Base.eltype(d::Dator{R}) where R = eltype(R)

