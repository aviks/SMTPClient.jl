@testset "Errors" begin
  @testset "Error message for Humans(TM)" begin
    let errmsg = "resolve host"
      server = "smtp://nonexists"
      body = IOBuffer("test")

      try
        send(server, ["nobody@earth"], "nobody@earth", body)
        @assert false, "send should fail"
      catch e
        @test occursin(string(errmsg), string(e))
      end
    end
  end


  @testset "Non-blocking send" begin
    let errmsg = "resolve host"
      server = "smtp://nonexists"
      body = IOBuffer("test")

      t = @async send(server, ["nobody@earth"], "nobody@earth", body)
      try
        wait(t)
      catch e
        @test e isa TaskFailedException
        @test occursin(errmsg, e.task.exception.msg)
      end
    end
  end
end  # @testset "Errors"
