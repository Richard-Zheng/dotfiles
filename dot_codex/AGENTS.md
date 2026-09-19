## SSH / remote command execution

For non-interactive remote shell commands, prefer `ssh-run` instead of
embedding the remote script in an `ssh` command-line argument.

Usage:

    ssh-run [SSH_OPTIONS...] destination <<'EOF'
    remote commands...
    EOF

SSH options are passed through directly to `ssh`, so options such as
`-p`, `-i`, `-J`, `-4`, and `-o ...` may be used when necessary.

`ssh-run` injects `-F /home/frain/.ssh/config` and 
`-o BatchMode=yes` by default.

Do not put substantial remote shell scripts directly in an SSH
command argument like:

    ssh HOST 'command1; command2; ...'

Use plain `ssh` when you specifically need SSH features such as
interactive sessions, tunneling, port forwarding, or `-N`.
