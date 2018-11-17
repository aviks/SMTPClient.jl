mutable struct SendOptions
  blocking::Bool
  isSSL::Bool
  username::String
  passwd::String

  SendOptions(; blocking::Bool = true, isSSL::Bool = false,
              username::AbstractString = "", passwd::AbstractString = "") =
  new(blocking, isSSL, String(username), String(passwd))
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
