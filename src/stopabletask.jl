struct StopableTask
    task::Task
    function StopableTask(t::Task)
        tls = Base.get_task_tls(t)
        tls[:should_stop] = false
        return new(t)
    end
end

function StopableTask(f, spawn=false)
    t = Task(f)
    if spawn
        t.sticky = false
    end
    return StopableTask(t)
end

Base.schedule(t::StopableTask) = schedule(t.task)
Base.schedule(t::StopableTask, arg; error=false) = schedule(t.task, arg; error)

function stop!(t::StopableTask)
    Base.get_task_tls(t.task)[:should_stop] = true
    return
end

Base.setproperty!(t::StopableTask, name::Symbol, x) = setproperty!(t.task, name, x)
function Base.getproperty(t::StopableTask, name::Symbol)
    task = getfield(t, :task)
    return name == :task ?
        task :
        getproperty(task, name)
end

should_stop() = task_local_storage(:should_stop)
should_stop!() = task_local_storage(:should_stop, true)
dont_stop!() = task_local_storage(:should_stop, false)

isfinished(t::StopableTask) = (st = status(t).state; st == :done || st == :failed)
