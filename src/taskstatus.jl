status(t::Task) =  (
    state = !istaskstarted(t) ?
      :init :
      t.state,
    result = t.result,
    usr = !isnothing(t.storage) && haskey(t.storage, :usr) ?
      t.storage[:usr] :
      nothing
)

status(t::StopableTask) = status(t.task)
