module Dators

import Base.Threads
using Distributed

using ResultTypes

export Dator

include("./thread.jl")
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
