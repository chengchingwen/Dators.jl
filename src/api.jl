Base.filter(f, d::Dator) = setfield(d, :do_post_f, (ch, x)->f(x) ? d.do_post_f(ch, x) : nothing)

Base.map(f, d::Dator) = setfield(d, :f, f∘d.f)

function batch(d::Dator, n, drop_last=true)
  buf = Vector{eltype(d)}(undef, n)
  function _batch(ch, f, src, do_post_f)
    c = 0
    for data in src
      result = f(data)
      c+=1
      
      if c <= n
        buf[c] = result
      end
      
      if c == n
        do_post_f(ch, copy(buf))
        c = 0
      end
    end

    if c != 0 && !drop_last
      do_post_f(ch, buf[1:c])
    end
  end

  return Dator(identity, d; mode=Thread(1), map_do_f=_batch, res_ctype=Vector{eltype(d)})
end
