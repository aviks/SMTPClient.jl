mutable struct SendOptions
  isSSL::Bool
  username::String
  passwd::String
end

function SendOptions(; isSSL::Bool = false, username::AbstractString = "",
                     passwd::AbstractString = "", kwargs...)
  kwargs = Dict(kwargs)
  if get(kwargs, :blocking, nothing) ≠ nothing
    @warn "options `blocking` is deprecated, blocking behaviour is default now, " *
          "use `@async send(...)` for non-blocking style."
    pop!(kwargs, :blocking)
  end
  length(keys(kwargs)) ≠ 0 && throw(MethodError("got unsupported keyword arguments"))
  SendOptions(isSSL, String(username), String(passwd))
end

function Base.show(io::IO, o::SendOptions)
  print(io, "SSL:      ", o.isSSL)
  !isempty(o.username) && print(io, "\nusername: ", o.username)
end

mutable struct SendResponse
  body::IO
  code::Int
  total_time::Float64

  SendResponse() = new(IOBuffer(), 0, 0.0)
end


function Base.show(io::IO, o::SendResponse)
  println(io, "Return Code: ", o.code)
  println(io, "Time:        ", o.total_time)
  print(io,   "Response:    ", String(take!(o.body)))
end


mutable struct ReadData
  typ::Symbol
  src::Any
  str::AbstractString
  offset::Csize_t
  sz::Csize_t

  ReadData() = new(:undefined, false, "", 0, 0)
end


mutable struct ConnContext
  curl::Ptr{CURL}
  url::String
  rd::ReadData
  resp::SendResponse
  options::SendOptions
  close_ostream::Bool
  bytes_recd::Int

  ConnContext(options::SendOptions) =
  new(C_NULL, " ", ReadData(), SendResponse(), options, false, 0)
end
