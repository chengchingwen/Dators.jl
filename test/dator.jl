@testset "dator" begin
    src = Dators.CreateSrc(Dators.Thread(1)) do
        Channel() do ch
            for i = 1:100
                put!(ch, i)
            end
        end
    end

    dator = Dators.Dator(x->x*x, 1, src;  compute_type=Dators.Thread(1))
    bd = Dators.batch(dator, 4)
    Dators.start!(bd)

    result = Bool[]
    for (i, d) in enumerate(bd)
        push!(result, d[1] == [x^2 for x in (4(i-1)+1):4i])
    end
    @test all(result)
end
