import asyncore
import base64
import smtpd
import sys

smtpd.DEBUGSTREAM = sys.stderr


class DebuggingChannel(smtpd.SMTPChannel):  # most of code is copied from cpython's smtpd.py
    AUTH_PLAIN = 1024

    authmap = {
        'foo@example.org': 'bar',
    }

    def found_terminator(self):
        line = self._emptystring.join(self.received_lines)
        print('Data:', repr(line), file=smtpd.DEBUGSTREAM)
        self.received_lines = []
        if self.smtp_state == self.COMMAND:
            sz, self.num_bytes = self.num_bytes, 0
            if not line:
                self.push('500 Error: bad syntax')
                return
            if not self._decode_data:
                line = str(line, 'utf-8')
            i = line.find(' ')
            if i < 0:
                command = line.upper()
                arg = None
            else:
                command = line[:i].upper()
                arg = line[i+1:].strip()
            max_sz = (self.command_size_limits[command]
                        if self.extended_smtp else self.command_size_limit)
            if sz > max_sz:
                self.push('500 Error: line too long')
                return
            method = getattr(self, 'smtp_' + command, None)
            if not method:
                self.push('500 Error: command "%s" not recognized' % command)
                return
            method(arg)
            return
        elif self.smtp_state == self.AUTH_PLAIN:
            self.smtp_AUTH_PLAIN(line)
        else:
            if self.smtp_state != self.DATA:
                self.push('451 Internal confusion')
                self.num_bytes = 0
                return
            if self.data_size_limit and self.num_bytes > self.data_size_limit:
                self.push('552 Error: Too much mail data')
                self.num_bytes = 0
                return
            # Remove extraneous carriage returns and de-transparency according
            # to RFC 5321, Section 4.5.2.
            data = []
            for text in line.split(self._linesep):
                if text and text[0] == self._dotsep:
                    data.append(text[1:])
                else:
                    data.append(text)
            self.received_data = self._newline.join(data)
            args = (self.peer, self.mailfrom, self.rcpttos, self.received_data)
            kwargs = {}
            if not self._decode_data:
                kwargs = {
                    'mail_options': self.mail_options,
                    'rcpt_options': self.rcpt_options,
                }
            status = self.smtp_server.process_message(*args, **kwargs)
            self._set_post_data_state()
            if not status:
                self.push('250 OK')
            else:
                self.push(status)

    def smtp_EHLO(self, arg):
        if not arg:
            self.push('501 Syntax: EHLO hostname')
            return
        # See issue #21783 for a discussion of this behavior.
        if self.seen_greeting:
            self.push('503 Duplicate HELO/EHLO')
            return
        self._set_rset_state()
        self.seen_greeting = arg
        self.extended_smtp = True
        self.push('250-%s' % self.fqdn)
        if self.data_size_limit:
            self.push('250-SIZE %s' % self.data_size_limit)
            self.command_size_limits['MAIL'] += 26
        if not self._decode_data:
            self.push('250-8BITMIME')
        if self.enable_SMTPUTF8:
            self.push('250-SMTPUTF8')
            self.command_size_limits['MAIL'] += 10
        self.push('250-AUTH PLAIN')
        self.push('250 HELP')

    def smtp_AUTH(self, arg):
        if not arg:
            self.push('501 Syntax: AUTH')
            return
        if arg != 'PLAIN':
            self.push('500 Error: "{}" not support'.format(arg))
            return
        self.smtp_state = self.AUTH_PLAIN
        self.push('334')

    def smtp_AUTH_PLAIN(self, arg):
        """
        e.g.
            235 Accepted
            535 Username and Password not accepted
        """
        def code535():
            self.push('535 Username and Password not accepted')

        self.smtp_state = self.COMMAND
        s = base64.b64decode(arg).split(b'\0')
        if len(s) != 3:
            code535()
            return

        s = map(bytes.decode, s)
        authzid, authcid, pw = s
        print('===>', authzid, authcid, pw)
        if self.authmap.get(authcid, None) != pw:
            code535()
            return

        self.push('235 Accepted')


class DebuggingServer(smtpd.DebuggingServer):
    channel_class = DebuggingChannel

    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        with open(self.mbox, 'w') as f:
            # RCPT TO
            for i in rcpttos:
                f.write('X-RCPT: ')
                f.write(i)
                f.write('\n')
            # content
            f.write(data.decode())
            f.write('\n')


if __name__ == '__main__':
    if len(sys.argv) >= 2:
        mbox = sys.argv[1]
    else:
        print('usage:', sys.argv[0], "<mbox>")
        exit(1)

    server = DebuggingServer(('0.0.0.0', 1025), ('0.0.0.0', 25))
    server.mbox = mbox
    asyncore.loop()
