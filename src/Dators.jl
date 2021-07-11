module Dators

import Base.Threads
using Distributed

export Dator

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
