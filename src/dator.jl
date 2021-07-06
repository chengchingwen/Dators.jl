struct Dator{R, S, F, F0, F1, M0, M}
  type::PMode
  map_do_pre_f::M0
  do_pre_f::F0
  map_do_f::M
  f::F
  do_post_f::F1
  srcs::S
  result::R
  execs::Vector{E} where E <: Executor
end

function create_executors(f, con, dst, mode; map_do_f=map_do_f, do_post_f=do_post_f)
  return map(i->Executor(f, con, dst, typeof(mode), i; map_do_f, do_post_f), ids(mode))
end

do_pre_f(ch, src) = put!(ch, src)
map_do_pre_f(ch, srcs, do_pre_f=do_pre_f) = foreach(Base.Fix1(do_pre_f, ch), srcs)

function Dator(f, srcs;
               mode=Async(2),
               csize=2num(mode), ctype=eltype(srcs),
               res_csize=32, res_ctype=first(Base.return_types(f, Tuple{ctype})),
               pid = Distributed.myid(),
               map_do_pre_f=map_do_pre_f,
               do_pre_f=do_pre_f,
               map_do_f=map_do_f,
               do_post_f=do_post_f)
  if mode isa Parallel
    chn = Distributed.RemoteChannel(pid) do
      Channel(csize=csize, ctype=ctype) do ch
        map_do_pre_f(ch, srcs, do_pre_f)
      end
    end
    dst = Distributed.RemoteChannel(pid) do
      Channel{res_ctype}(res_csize)
    end
  else
    chn = Channel(csize=csize, ctype=ctype) do ch
      map_do_pre_f(ch, srcs, do_pre_f)
    end
    dst = Channel{res_ctype}(res_csize)
  end

  execs = create_executors(f, chn, dst, mode; map_do_f, do_post_f)
  Dator(mode, map_do_pre_f, do_pre_f, map_do_f, f, do_post_f, srcs, dst, execs)
end


