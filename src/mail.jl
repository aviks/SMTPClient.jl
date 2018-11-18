send(url::AbstractString, to::AbstractVector{<:AbstractString},
              from::AbstractString, body::IO, opts::SendOptions = SendOptions()) =
  do_send(String(url), map(String, collect(to)), String(from), opts, ReadData(body))

function do_send(url::String, to::Vector{String}, from::String, options::SendOptions,
                 rd::ReadData)
  ctxt = nothing
  try
    ctxt = ConnContext(url = url, rd = rd, options = options)

    setmail_from!(ctxt, from)
    setmail_rcpt!(ctxt, to)

    connect(ctxt)
    getresponse!(ctxt)

    ctxt.resp
  finally
    cleanup!(ctxt)
  end
end
