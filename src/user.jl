function encode_attachment(filename::String, boundary::String)
    io = IOBuffer()
    iob64_encode = Base64EncodePipe(io)
    open(filename, "r") do f
        write(iob64_encode, f)
    end
    close(iob64_encode)

    filename_ext = split(filename, '.')[end]

    if haskey(mime_types, filename_ext)
        content_type = mime_types[filename_ext]
    else
        content_type = "application/octet-stream"
    end

    if haskey(mime_types, filename_ext) && startswith(mime_types[filename_ext], "image")
        content_disposition = "inline"
    else
        content_disposition = "attachment"
    end

    encoded_str = 
        "--$boundary\r\n" *
        "Content-Disposition: $content_disposition;\r\n" *
        "    filename=$(basename(filename))\r\n" *
        "Content-Type: $content_type;\r\n" *
        "    name=\"$(basename(filename))\"\r\n" *
        "Content-Transfer-Encoding: base64\r\n" *
        "$(String(take!(io)))\r\n" *
        "--$boundary\r\n"
    return encoded_str
end

# See https://www.w3.org/Protocols/rfc1341/7_1_Text.html about charset
function get_message(message::String, ::Val{:plain}, charset::String = "UTF-8")
    mime_msg = 
        "Content-Type: text/plain; charset=\"$charset\"" *
        "Content-Transfer-Encoding: quoted-printable\r\n\r\n" *
        "$message\r\n"
    return mime_msg
end

get_message(message::String, ::Val{:utf8}) =
    get_message(message, Val(:plain), "UTF-8")

get_message(message::String, ::Val{:usascii}) =
    get_message(message, Val(:plain), "US-ASCII")

function get_message(message::String, ::Val{:html})
    mime_msg = 
        "Content-Type: text/html;\r\n" *
        "Content-Transfer-Encoding: 7bit;\r\n\r\n" *
        "\r\n" *
        message *
        "\r\n"
    return mime_msg
end

#Provide the message body as RFC5322 within an IO

"""
"""
function get_body(
        to::Vector{String},
        from::String,
        subject::String,
        mime_msg::String;
        cc::Vector{String} = String[],
        replyto::String = "",
        attachment::Vector{String} = String[]
    )

    boundary = "Julia_SMTPClient-" * join(rand(collect(vcat('0':'9','A':'Z','a':'z')), 40))

    contents = 
        "From: $from\r\n" *
        "Date: Fri, 18 Oct 2013 21:44:29 +0100\r\n" *
        "Subject: $subject\r\n" *
        ifelse(length(cc) > 0, "Cc: $(join(cc, ", "))\r\n", "") *
        ifelse(length(replyto) > 0, "Reply-To: $replyto\r\n", "") *
        "To: $(join(to, ", "))\r\n"

    if length(attachment) == 0
        contents *=
            "MIME-Version: 1.0\r\n" *
            "$mime_msg\r\n\r\n"
    else
        contents *=
            "Content-Type: multipart/mixed; boundary=\"$boundary\"\r\n\r\n" *
            "MIME-Version: 1.0\r\n" *
            "\r\n" *
            "This is a message with multiple parts in MIME format.\r\n" *
            "--$boundary\r\n" * 
            "$mime_msg\r\n" *
            "--$boundary\r\n" * 
            "\r\n" *
            join(encode_attachment.(attachment, boundary), "\r\n")
    end
    body = IOBuffer(contents)
    return body
end