module Dators

import Base.Threads
import Distributed

export Dator

include("./iterate.jl")
include("./types.jl")
include("./executor.jl")
include("./dator.jl")
include("./api.jl")

end
