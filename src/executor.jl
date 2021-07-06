struct Executor{F, T}
  f::F
  task::T
end

do_post_f(ch, result) = put!(ch, result)
map_do_f(ch, f, src, do_post_f=do_post_f) = foreach(Base.Fix1(do_post_f, ch)∘f, src)

function Executor(f, con, dst, mode::Type{Async}, id=0; map_do_f=map_do_f, do_post_f=do_post_f)
  task = @async while true
    for src in con
      map_do_f(dst, f, src, do_post_f)
    end
  end
  return Executor(f, task)
end

function Executor(f, con, dst, mode::Type{Thread}, id=0; map_do_f=map_do_f, do_post_f=do_post_f)
  task = Threads.@spawn while true
    for src in con
      map_do_f(dst, f, src, do_post_f)
    end
  end
  return Executor(f, task)
end

function Executor(f, con, dst, mode::Type{Process}, id=0; map_do_f=map_do_f, do_post_f=do_post_f)
  task = Distributed.@spawnat :any while true
    for src in con
      map_do_f(dst, f, src, do_post_f)
    end    
  end
  return Executor(f, task)
end

function Executor(f, con, dst, mode::Type{ProcessWithIDs}, id; map_do_f=map_do_f, do_post_f=do_post_f)
  task = Distributed.@spawnat id while true
    for src in con
      map_do_f(dst, f, src, do_post_f)
    end
  end
  return Executor(f, task)
end
