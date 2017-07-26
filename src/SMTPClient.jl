module SMTPClient

using LibCURL

import Base.convert, Base.show

export send
export SendOptions, SendResponse

def_rto = 0.0

##############################
# Struct definitions
##############################

mutable struct SendOptions
    blocking::Bool
    isSSL::Bool
    username::AbstractString
    passwd::AbstractString

    SendOptions(; blocking=true,isSSL=false,  username="", passwd="") =
        new(blocking, isSSL, username, passwd)
end

mutable struct SendResponse
    body::IO
    code::Int
    total_time::Float64
    SendResponse() = new(IOBuffer(), 0, 0.0)
end


function show(io::IO, o::SendResponse)
    println(io, "Return Code   :", o.code)
    println(io, "Time :", o.total_time)
    println(io, "Response:", String(take!(o.body)))
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
    url::AbstractString
    rd::ReadData
    resp::SendResponse
    options::SendOptions
    close_ostream::Bool
    bytes_recd::Integer

    ConnContext(options::SendOptions) =
        new(C_NULL, " ", ReadData(), SendResponse(), options, false, 0)
end



##############################
# Callbacks
##############################

function write_cb(buff::Ptr{UInt8}, sz::Csize_t, n::Csize_t, p_ctxt::Ptr{Void})
#    println("@write_cb")
    ctxt = unsafe_pointer_to_objref(p_ctxt)
    nbytes = sz * n
    write(ctxt.resp.body, buff, nbytes)
    ctxt.bytes_recd = ctxt.bytes_recd + nbytes

    nbytes::Csize_t
end

c_write_cb = cfunction(write_cb, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Void}))


function curl_read_cb(out::Ptr{Void}, s::Csize_t, n::Csize_t, p_ctxt::Ptr{Void})
#    println("@curl_read_cb")

    ctxt = unsafe_pointer_to_objref(p_ctxt)
    bavail::Csize_t = s * n
    breq::Csize_t = ctxt.rd.sz - ctxt.rd.offset
    b2copy = bavail > breq ? breq : bavail

    if ctxt.rd.typ == :buffer
        ccall(:memcpy, Ptr{Void}, (Ptr{Void}, Ptr{Void}, UInt),
                out, convert(Ptr{UInt8}, ctxt.rd.str) + ctxt.rd.offset, b2copy)
    elseif ctxt.rd.typ == :io
        b_read = read(ctxt.rd.src, UInt8, b2copy)
        ccall(:memcpy, Ptr{Void}, (Ptr{Void}, Ptr{Void}, UInt), out, b_read, b2copy)
    end
    ctxt.rd.offset = ctxt.rd.offset + b2copy

    r = convert(Csize_t, b2copy)
    r::Csize_t
end


c_curl_read_cb =
    cfunction(curl_read_cb, Csize_t, (Ptr{Void}, Csize_t, Csize_t, Ptr{Void}))


function curl_multi_timer_cb(curlm::Ptr{Void}, timeout_ms::Clong, p_muctxt::Ptr{Void})
    muctxt = unsafe_pointer_to_objref(p_muctxt)
    muctxt.timeout = timeout_ms / 1000.0

#    println("Requested timeout value : " * string(muctxt.timeout))

    ret = convert(Cint, 0)
    ret::Cint
end

c_curl_multi_timer_cb =
    cfunction(curl_multi_timer_cb, Cint, (Ptr{Void}, Clong, Ptr{Void}))


##############################
# Utility functions
##############################

macro ce_curl(f, handle, args...)
    local esc_args = [esc(arg) for arg in args]
    quote
        cc = $(esc(f))($(esc(handle)), $(esc_args...))

        if cc != CURLE_OK
            error(string($f) * "() failed: " * string(curl_easy_strerror(cc)))
        end
    end
end

macro ce_curlm(f, handle, args...)
    local esc_args = [esc(arg) for arg in args]
    quote
        cc = $(esc(f))($(esc(handle)), $(esc_args...))

        if(cc != CURLM_OK)
            error(string($f) * "() failed: " * string(curl_multi_strerror(cc)))
        end
    end
end


null_cb(curl) = nothing

function set_opt_blocking(options::SendOptions)
        o2 = deepcopy(options)
        o2.blocking = true
        return o2
end


function setup_easy_handle(url, options::SendOptions)
    ctxt = ConnContext(options)

    curl = curl_easy_init()
    if (curl == C_NULL) throw("curl_easy_init() failed") end

    ctxt.curl = curl

    ctxt.url = url

    p_ctxt = pointer_from_objref(ctxt)


    @ce_curl curl_easy_setopt curl CURLOPT_URL url
    @ce_curl curl_easy_setopt curl CURLOPT_WRITEFUNCTION c_write_cb
    @ce_curl curl_easy_setopt curl CURLOPT_UPLOAD 1
    @ce_curl curl_easy_setopt curl CURLOPT_WRITEDATA p_ctxt

    if options.isSSL
        @ce_curl curl_easy_setopt curl CURLOPT_USE_SSL CURLUSESSL_ALL
    end

    if length(options.username) > 0
        @ce_curl curl_easy_setopt curl CURLOPT_USERNAME options.username
        @ce_curl curl_easy_setopt curl CURLOPT_PASSWORD options.passwd
    end

    ctxt
end


function cleanup_easy_context(ctxt::Union{ConnContext,Bool})
    if isa(ctxt, ConnContext)

        if (ctxt.curl != C_NULL)
            curl_easy_cleanup(ctxt.curl)
        end

        if ctxt.close_ostream
            close(ctxt.resp.body)
            ctxt.resp.body = nothing
            ctxt.close_ostream = false
        end
    end
end


function process_response(ctxt)
    http_code = Array{Int}(1)
    @ce_curl curl_easy_getinfo ctxt.curl CURLINFO_RESPONSE_CODE http_code

    total_time = Array{Float64}(1)
    @ce_curl curl_easy_getinfo ctxt.curl CURLINFO_TOTAL_TIME total_time

    ctxt.resp.code = http_code[1]
    ctxt.resp.total_time = total_time[1]
end


##############################
# Library initializations
##############################

init() = curl_global_init(CURL_GLOBAL_ALL)
cleanup() = curl_global_cleanup()

function send(url::AbstractString, to::Vector, from::AbstractString, body::IO,
              options::SendOptions=SendOptions())
    if (options.blocking)
        rd::ReadData = ReadData()

        rd.typ = :io
        rd.src = body
        seekend(body)
        rd.sz = position(body)
        seekstart(body)

        _do_send(url, to, from, options, rd)
    else
        remotecall(myid(), send, url, to, from, body, set_opt_blocking(options))
    end
end


function _do_send(url::AbstractString, to::Vector, from::AbstractString,
                  options::SendOptions, rd::ReadData)
    ctxt = false
    slist::Ptr{Void} = C_NULL
    try
        ctxt = setup_easy_handle(url, options)
        ctxt.rd = rd
        # rd.typ is always IO for smtp

        p_ctxt = pointer_from_objref(ctxt)
        @ce_curl curl_easy_setopt ctxt.curl CURLOPT_READDATA p_ctxt

        @ce_curl curl_easy_setopt ctxt.curl CURLOPT_READFUNCTION c_curl_read_cb

        for tos in to
            slist = curl_slist_append(slist, tos)
        end

        @ce_curl curl_easy_setopt ctxt.curl CURLOPT_MAIL_RCPT slist

        @ce_curl curl_easy_setopt ctxt.curl CURLOPT_MAIL_FROM from


        # return exec_as_multi(ctxt)

        @ce_curl curl_easy_perform ctxt.curl
        process_response(ctxt)
        return ctxt.resp
    finally
        if (slist != C_NULL)
            curl_slist_free_all(slist)
        end
        cleanup_easy_context(ctxt)
    end
end


function exec_as_multi(ctxt)
    curl = ctxt.curl
    curlm = curl_multi_init()

    if (curlm == C_NULL) error("Unable to initialize curl_multi_init()") end

    try
        if isa(ctxt.options.callback, Function) ctxt.options.callback(curl) end

        @ce_curlm curl_multi_add_handle curl

        n_active = Array{Int}(1)
        n_active[1] = 1

        no_to = 30 * 24 * 3600.0
        request_timeout = 0.001 + (ctxt.options.request_timeout == 0.0 ? no_to : ctxt.options.request_timeout)

        started_at = time()
        time_left = request_timeout

    # poll_fd is unreliable when multiple parallel fds are active, hence using curl_multi_perform


# START curl_multi_perform  mode

        cmc = curl_multi_perform(curlm, n_active);
        while (n_active[1] > 0) &&  (time_left > 0)
            nb1 = ctxt.bytes_recd
            cmc = curl_multi_perform(curlm, n_active);
            if(cmc != CURLM_OK) error("curl_multi_perform() failed: " * string(curl_multi_strerror(cmc))) end

            nb2 = ctxt.bytes_recd

            if (nb2 > nb1)
                yield() # Just yield to other tasks
            else
                sleep(0.005) # Just to prevent unnecessary CPU spinning
            end

            time_left = request_timeout - (time() - started_at)
        end

# END OF curl_multi_perform


        if (n_active[1] == 0)
            msgs_in_queue = Array{Cint}(1)
            p_msg::Ptr{CURLMsg2} = curl_multi_info_read(curlm, msgs_in_queue)

            while (p_msg != C_NULL)
#                println("Messages left in Q : " * string(msgs_in_queue[1]))
                msg = unsafe_load(p_msg)

                if (msg.msg == CURLMSG_DONE)
                    ec = convert(Int, msg.data)
                    if (ec != CURLE_OK)
#                        println("Result of transfer: " * string(msg.data))
                        throw("Error executing request : " * string(curl_easy_strerror(ec)))
                    else
                        process_response(ctxt)
                    end
                end

                p_msg = curl_multi_info_read(curlm, msgs_in_queue)
            end
        else
            error("request timed out")
        end

    finally
        curl_multi_remove_handle(curlm, curl)
        curl_multi_cleanup(curlm)
    end

    ctxt.resp
end


end  # module SMTPClient
