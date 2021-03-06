# Dators.jl

[![CI](https://github.com/chengchingwen/Dators.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/chengchingwen/Dators.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/chengchingwen/Dators.jl/branch/master/graph/badge.svg?token=37ITLZ0VTO)](https://codecov.io/gh/chengchingwen/Dators.jl)

A data implementation.

```julia
julia> using Dators

julia> src = Dators.CreateSrc() do
           Channel() do ch
               for i = 1:100
                   put!(ch, i)
               end
           end
       end;

julia> dator = Dators.Dator(x->x*x, 1, src;  compute_type=Dators.Thread(2));

julia> bd = Dators.batch(dator, 4);

julia> Dators.start!(bd)

julia> for d in bd
           @show d
       end
d = ([121, 144, 169, 196],)
d = ([256, 289, 324, 400],)
d = ([441, 484, 529, 576],)
d = ([1, 9, 16, 25],)
d = ([36, 49, 64, 81],)
d = ([100, 4, 784, 900],)
d = ([961, 1024, 1089, 1156],)
d = ([1225, 625, 2500, 2601],)
d = ([2809, 2916, 3025, 3136],)
d = ([225, 1296, 3249, 676],)
d = ([3364, 3721, 3969, 4096],)
d = ([4356, 4624, 4761, 5041],)
d = ([5929, 6241, 6561, 6889],)
d = ([7056, 7569, 7744, 8281],)
d = ([3481, 3600, 729, 361],)
d = ([1444, 1521, 1600, 3844],)
d = ([1681, 1764, 1849, 1936],)
d = ([2025, 841, 1369, 2116],)
d = ([2209, 2304, 2401, 2704],)
d = ([4225, 4489, 4900, 5184],)
d = ([5476, 5329, 5625, 5776],)
d = ([6084, 6400, 6724, 7225],)
d = ([7396, 7921, 8100, 8464],)
d = ([8836, 9025, 9216, 9409],)

julia> bd2 = Dators.batch(dator, 4, false);

julia> Dators.restart!(bd2)

julia> for d in bd2
           @show d
       end
d = ([4, 9, 16, 49],)
d = ([81, 100, 121, 144],)
d = ([1, 25, 36, 64],)
d = ([169, 196, 225, 256],)
d = ([289, 324, 361, 400],)
d = ([441, 484, 529, 576],)
d = ([625, 784, 841, 729],)
d = ([961, 1024, 1156, 1089],)
d = ([676, 900, 1225, 1369],)
d = ([1296, 1444, 1521, 1681],)
d = ([1600, 2025, 1849, 1936],)
d = ([2116, 2209, 2304, 2500],)
d = ([1764, 2401, 2601, 3249],)
d = ([2704, 3025, 2809, 3136],)
d = ([2916, 3481, 3600, 3721],)
d = ([3844, 3969, 4225, 4356],)
d = ([4624, 4489, 4761, 5041],)
d = ([4900, 5184, 5476, 5625],)
d = ([6084, 6400, 6561, 6889],)
d = ([6724, 7056, 7225, 7396],)
d = ([7744, 7921, 8100, 8281],)
d = ([8464, 8836, 9025, 9216],)
d = ([3364, 4096, 5329, 5776],)
d = ([5929, 6241, 7569, 8649],)
d = ([9409, 10000, 9801],)
d = ([9604],)

```

