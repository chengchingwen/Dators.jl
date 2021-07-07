struct Executor{F, T}
  f::F
  task::T
end

map_do_map_f(ch, f, con, do_post_f=do_post_f) = foreach(src->map_do_f(ch, f, src, do_post_f) ,  con)

do_post_f(ch, result) = put!(ch, result)
map_do_f(ch, f, src, do_post_f=do_post_f) = foreach(Base.Fix1(do_post_f, ch)∘f, src)

function Executor(f, con, dst, mode::Type{Async}, id=0; map_do_f=map_do_f, do_post_f=do_post_f)
  task = @async begin
      map_do_f(dst, f, con, do_post_f)
  end
  return Executor(f, task)
end

function Executor(f, con, dst, mode::Type{Thread}, id=0; map_do_f=map_do_f, do_post_f=do_post_f)
  task = Threads.@spawn begin
      map_do_f(dst, f, con, do_post_f)
  end
  return Executor(f, task)
end

function Executor(f, con, dst, mode::Type{Process}, id=0; map_do_f=map_do_f, do_post_f=do_post_f)
  task = Distributed.@spawnat :any begin
      map_do_f(dst, f, con, do_post_f)
  end
  return Executor(f, task)
end

function Executor(f, con, dst, mode::Type{ProcessWithIDs}, id; map_do_f=map_do_f, do_post_f=do_post_f)
  task = Distributed.@spawnat id begin
      map_do_f(dst, f, con, do_post_f)
  end
  return Executor(f, task)
end

Base.wait(e::Executor) = wait(e.task)

Base.show(io::IO, e::Executor) =
  print(io, "Executor{", typeof(e.f),"}(", e.task, ")")
