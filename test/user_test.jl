include("../src/SMTPClient.jl")
#= import Base64: Base64EncodePipe
import Dates
include("../src/mime_types.jl")
include("../src/user.jl") =#
using .SMTPClient

opt = SendOptions(
  isSSL = true,
  username = "rmsrosauk@gmail.com",
  passwd = "adgjta1212"
)

url = "smtps://smtp.gmail.com:465"
from = "<rmsrosauk@gmail.com>"

message = "Here is a version for the PR, with attachment"
to = ["<rrosa@im.ufrj.br>", "<rmsrosa@gmail.com>"]
cc = ["<rrosa@ufrj.br>"]
bcc = ["<rmsrosa@gmail.com>"]
rcpt = vcat(to, cc, bcc)
rcpt = copy(to)
replyto = "<rrosa@im.ufrj.br>"
subject = "Test SMTPClient.jl"
attachment = ["../README.md"]
mime_message = get_mime_msg(message, Val(:utf8))
body = get_body(to, from, subject, mime_message)#; cc, replyto) #, attachment)
resp = send(url, rcpt, from, body, opt)