module Dators

import Base.Threads
using Distributed

using ResultTypes

export Dator, CreateSrc

const DEBUG = Ref{Bool}(false)

debug!(flag=true) = global DEBUG[] = flag

function __init__()
    global DEBUG
    haskey(ENV, "JULIA_DEBUG") && ENV["JULIA_DEBUG"] == "Dators" && debug!()
end


macro debuginfo(body...)
    global DEBUG

    args = Expr[]
    for ex in body
        if ex isa Expr && ex.head == :(=)
            narg = length(ex.args)
            if narg == 1 && ex.args[1] isa Symbol
                key = ex.args[1]
                tls_key = QuoteNode(key)
                tls_value = esc(key)
                push!(args,
                      :(task_local_storage($(tls_key), $(tls_value))))
            elseif narg == 2 && ex.args[1] isa Symbol
                key, value = ex.args
                tls_key = QuoteNode(key)
                if value isa Symbol
                    tls_value = QuoteNode(value)
                elseif value isa Expr && value.head == :($)
                    tls_value = esc(value.args[1])
                else
                    continue
                end
                push!(args,
                      :(task_local_storage($(tls_key), $(tls_value))))
            end
        end
    end

    return quote
        $(DEBUG)[] && begin
            $(args...)
        end
    end
end

include("./thread.jl")
include("./channels.jl")
include("./channel_result.jl")
include("./stopabletask.jl")
include("./channel.jl")
include("./taskstatus.jl")
include("./remotetask.jl")
include("./types.jl")
include("./connect.jl")
include("./executor.jl")
include("./dator.jl")
include("./source.jl")
include("./api.jl")

end
