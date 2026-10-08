## SSH / remote command execution

For non-interactive remote shell commands, use:

    ssh -o BatchMode=yes -o ConnectTimeout=10 HOST 'bash -se' <<'EOF'
    remote commands...
    EOF

`BatchMode=yes` fails fast instead of hanging on an auth prompt;
`ConnectTimeout=10` bounds the connection. Use a quoted heredoc (`<<'EOF'`)
so the local shell does not expand variables, and `bash -se` so the remote
script stops on the first failing command. The delimiter can be something
other than `EOF` when needed.

Do not put substantial remote shell scripts directly in an `ssh`
command argument like:

    ssh HOST 'command1; command2; ...'

Use plain `ssh` when you specifically need SSH features such as
interactive sessions, tunneling, port forwarding, or `-N`.
