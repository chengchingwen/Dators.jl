
thread1!(task::Task) = ccall(:jl_set_task_tid, Cvoid, (Any, Cint), task, 0)

macro thread1(expr)
    letargs = Base._lift_one_interp!(expr)

    thunk = esc(:(()->($expr)))
    quote
        let $(letargs...)
            local task = Task($thunk)
            thread1!(task)
            schedule(task)
            task
        end
    end
end

macro thread1_do(expr)
    letargs = Base._lift_one_interp!(expr)

    thunk = esc(:(()->($expr)))
    quote
        let $(letargs...)
            local task = Task($thunk)
            thread1!(task)
            schedule(task)
            wait(task)
            Base.task_result(task)
        end
    end
end

function thread1(f)
    task = Task(f)
    thread1!(task)
    schedule(task)
    wait(task)
    return Base.task_result(task)
end
