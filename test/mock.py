import asyncio
import base64
import sys
from aiosmtpd.controller import Controller
from aiosmtpd.smtp import SMTP as SMTPServer, AuthResult, LoginPassword


class DebuggingHandler:
    """Custom handler for processing SMTP messages with authentication support."""

    def __init__(self, mbox):
        self.mbox = mbox
        self.authmap = {
            'foo@example.org': 'bar',
        }

    async def handle_DATA(self, server, session, envelope):
        """Process incoming message data."""
        try:
            print(f'Data received from: {envelope.mail_from}', file=sys.stderr)
            print(f'Data received for: {envelope.rcpt_tos}', file=sys.stderr)
            print(f'Data size: {len(envelope.content)} bytes', file=sys.stderr)

            with open(self.mbox, 'w') as f:
                # RCPT TO
                for recipient in envelope.rcpt_tos:
                    f.write('X-RCPT: ')
                    f.write(recipient)
                    f.write('\n')
                # content
                f.write(envelope.content.decode('utf-8', errors='replace'))
                f.write('\n')

            return '250 OK'
        except Exception as e:
            print(f'Error processing message: {e}', file=sys.stderr)
            return '451 Requested action aborted: error in processing'


def authenticator_callback(server, session, envelope, mechanism, auth_data):
    """
    Authenticator callback for aiosmtpd.

    This function is called by aiosmtpd when a client attempts to authenticate.
    For PLAIN and LOGIN mechanisms, auth_data is a LoginPassword object.
    """
    print(f'AUTH {mechanism} attempt from {session.peer}', file=sys.stderr)

    # Get the handler instance which has the authmap
    handler = server.event_handler

    if mechanism not in ('PLAIN', 'LOGIN'):
        print(f'AUTH {mechanism} not supported', file=sys.stderr)
        result = AuthResult(success=False, handled=True, auth_data=None)
        print(f'Returning: {result}', file=sys.stderr)
        return result

    # auth_data is a LoginPassword object with .login and .password attributes
    if isinstance(auth_data, LoginPassword):
        username = auth_data.login
        password = auth_data.password

        # Decode bytes to strings (same as old code: map(bytes.decode, s))
        if isinstance(username, bytes):
            username = username.decode('utf-8')
        if isinstance(password, bytes):
            password = password.decode('utf-8')

        print(f'AUTH attempt: username={username}, password={password}', file=sys.stderr)

        # Check credentials against authmap
        if handler.authmap.get(username) == password:
            print(f'AUTH succeeded for {username}', file=sys.stderr)
            result = AuthResult(success=True, auth_data=username)
            print(f'Returning: {result}', file=sys.stderr)
            return result
        else:
            print(f'AUTH failed: invalid credentials for {username}', file=sys.stderr)
            result = AuthResult(success=False, handled=False, auth_data=None)
            print(f'Returning: {result}', file=sys.stderr)
            return result

    print(f'AUTH failed: unexpected auth_data type', file=sys.stderr)
    result = AuthResult(success=False, handled=False )
    print(f'Returning: {result}', file=sys.stderr)
    return result


class AuthenticatedSMTP(SMTPServer):
    """Custom SMTP server with AUTH PLAIN support."""

    def __init__(self, handler, **kwargs):
        # Set our preferred defaults, but allow kwargs to override
        defaults = {
            'decode_data': False,
            'enable_SMTPUTF8': True,
            'auth_required': False,  # Authentication optional, not required
            'auth_require_tls': False,  # Allow AUTH without TLS for testing
            'authenticator': authenticator_callback,  # Set the authenticator callback
        }
        # Merge defaults with incoming kwargs (kwargs take precedence)
        defaults.update(kwargs)
        # Enable authentication
        super().__init__(handler, **defaults)


class DebuggingController(Controller):
    """Controller that uses our custom SMTP server class."""

    def factory(self):
        """Factory method to create SMTP server instances."""
        return AuthenticatedSMTP(self.handler, **self.SMTP_kwargs)


if __name__ == '__main__':
    if len(sys.argv) >= 2:
        mbox = sys.argv[1]
    else:
        print('usage:', sys.argv[0], "<mbox>")
        exit(1)

    handler = DebuggingHandler(mbox)

    # Create controller that listens on port 1025
    controller = DebuggingController(
        handler,
        hostname='127.0.0.1',
        port=1025
    )

    print(f'Starting SMTP server on 127.0.0.1:1025', file=sys.stderr)
    print(f'Saving messages to: {mbox}', file=sys.stderr)

    # Start the controller (runs in a separate thread)
    controller.start()

    try:
        # Keep the main thread alive
        asyncio.get_event_loop().run_forever()
    except KeyboardInterrupt:
        print('\nShutting down SMTP server...', file=sys.stderr)
        controller.stop()
