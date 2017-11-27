using Base.Test

using SMTPClient


@testset "Error message for Humans(TM)" begin
    let errmsg = "Couldn't resolve host name"
        o = SendOptions()
        server = "smtp://nonexists"
        body = IOBuffer("test")

        try
            SMTPClient.send(server, ["nobody@earth"], "nobody@earth", body, o)
            @assert false, "send should fail"
        catch e
            @test contains(string(e), errmsg)
        end
    end
end
