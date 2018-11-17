using Test
using SMTPClient


@testset "SMTPClient" begin
  for t ∈ (:send, :error)
    @info "testset: $t..."
    include("./$t.jl")
  end
end
