mutable struct SendOptions
  isSSL::Bool
  username::String
  passwd::String
  verbose::Bool
end

function SendOptions(; isSSL::Bool = false, username::AbstractString = "",
                     passwd::AbstractString = "", verbose::Bool = false, kwargs...)
  kwargs = Dict(kwargs)
  if get(kwargs, :blocking, nothing) ≠ nothing
    @warn "options `blocking` is deprecated, blocking behaviour is default now, " *
          "use `@async send(...)` for non-blocking style."
    pop!(kwargs, :blocking)
  end
  length(keys(kwargs)) ≠ 0 && throw(MethodError("got unsupported keyword arguments"))
  SendOptions(isSSL, String(username), String(passwd), verbose)
end

function Base.show(io::IO, o::SendOptions)
  println(io, "SSL:      ", o.isSSL)
  print(  io, "verbose:  ", o.verbose)
  !isempty(o.username) && print(io, "\nusername: ", o.username)
end

mutable struct SendResponse
  body::IOBuffer
  code::Int
  total_time::Float64

  SendResponse() = new(IOBuffer(), 0, 0.0)
end

function Base.show(io::IO, o::SendResponse)
  println(io, "Return Code: ", o.code)
  println(io, "Time:        ", o.total_time)
  print(io,   "Response:    ", String(take!(o.body)))
end


mutable struct ReadData{T<:IO}
  typ::Symbol
  src::T
  str::AbstractString
  offset::Csize_t
  sz::Csize_t
end

ReadData() = ReadData{IOBuffer}(:undefined, IOBuffer(), "", 0, 0)
ReadData(io::T) where {T<:IO} = ReadData{T}(:io, io, "", 0, 0)
ReadData(io::IOBuffer)        = ReadData{IOBuffer}(:io, io, "", 0, io.size)


mutable struct ConnContext
  curl::Ptr{CURL}  # CURL handle
  url::String
  rd::ReadData
  resp::SendResponse
  options::SendOptions
  close_ostream::Bool
  bytes_recd::Int
  finalizer::Vector{Function}
end

function ConnContext(; curl = curl_easy_init(),
                     url::String = "",
                     rd::ReadData = ReadData(),
                     resp::SendResponse = SendResponse(),
                     options::SendOptions = SendOptions())
  curl == C_NULL && throw("curl_easy_init() failed")

  ctxt = ConnContext(curl, url, rd, resp, options, false, 0, Function[])

  @ce_curl curl_easy_setopt curl CURLOPT_URL url
  @ce_curl curl_easy_setopt curl CURLOPT_WRITEFUNCTION c_curl_write_cb
  @ce_curl curl_easy_setopt curl CURLOPT_WRITEDATA ctxt
  @ce_curl curl_easy_setopt curl CURLOPT_READFUNCTION c_curl_read_cb
  @ce_curl curl_easy_setopt curl CURLOPT_READDATA ctxt
  @ce_curl curl_easy_setopt curl CURLOPT_UPLOAD 1

  if options.isSSL
    @ce_curl curl_easy_setopt curl CURLOPT_USE_SSL CURLUSESSL_ALL
  end

  if !isempty(options.username)
    @ce_curl curl_easy_setopt curl CURLOPT_USERNAME options.username
    @ce_curl curl_easy_setopt curl CURLOPT_PASSWORD options.passwd
  end

  if options.verbose
    @ce_curl curl_easy_setopt curl CURLOPT_VERBOSE 1
  end

  ctxt
end

function setopt!(ctxt::ConnContext, opt, val)
  @ce_curl curl_easy_setopt ctxt.curl opt val
  ctxt
end

setmail_from!(ctxt::ConnContext, from::String) =
  setopt!(ctxt, CURLOPT_MAIL_FROM, from)

function setmail_rcpt!(ctxt::ConnContext, R::Vector{String})
  R′ = foldl(curl_slist_append, R, init = C_NULL)
  R′ == C_NULL && error("mail rcpts invalid")
  setopt!(ctxt, CURLOPT_MAIL_RCPT, R′)
  push!(ctxt.finalizer, () -> curl_slist_free_all(R′))
  ctxt
end

function connect(ctxt::ConnContext)
  @ce_curl curl_easy_perform ctxt.curl
  ctxt
end

cleanup!(::Nothing) = nothing
function cleanup!(ctxt::ConnContext)
  curl = ctxt.curl
  curl ≠ C_NULL && curl_easy_cleanup(curl)

  for f ∈ ctxt.finalizer
    f()
  end
  empty!(ctxt.finalizer)

  if ctxt.close_ostream
    close(ctxt.resp.body)
    ctxt.resp.body = nothing
    ctxt.close_ostream = false
  end
end

function getresponse!(ctxt::ConnContext)
  code = Array{Int}(undef, 1)
  @ce_curl curl_easy_getinfo ctxt.curl CURLINFO_RESPONSE_CODE code

  total_time = Array{Float64}(undef, 1)
  @ce_curl curl_easy_getinfo ctxt.curl CURLINFO_TOTAL_TIME total_time

  ctxt.resp.code = code[1]
  ctxt.resp.total_time = total_time[1]
end
