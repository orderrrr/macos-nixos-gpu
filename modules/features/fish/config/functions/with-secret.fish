function with-secret --description 'Run a command with secrets pulled from the dev-secrets keychain only for this invocation'
    if test (count $argv) -lt 2
        echo "usage: with-secret NAME[=KEYRING_KEY][,NAME[=KEYRING_KEY]...] command [args...]" >&2
        echo "examples:" >&2
        echo "  with-secret NPM_AUTH_TOKEN npm install" >&2
        echo "  with-secret NPM_TOKEN=NPM_AUTH_TOKEN npm publish" >&2
        echo "  with-secret GITLAB_API_KEY,CLICKUP_API_KEY some-tool" >&2
        return 2
    end

    set -l specs (string split , -- $argv[1])
    set -l rest $argv[2..]
    # macOS security emits multiline generic-password data as hexadecimal.
    # Decode only explicitly catalogued multiline secrets so ordinary hex-like
    # API tokens are never transformed accidentally.
    set -l multiline_keyring_keys \
        OCI_ADMIN_CONFIG OCI_ADMIN_PRIVATE_KEY \
        OCI_RESTRICTED_CONFIG OCI_RESTRICTED_PRIVATE_KEY

    for spec in $specs
        set -l parts (string split -m 1 = -- $spec)
        set -l env_name $parts[1]
        set -l keyring_key $parts[1]
        if test (count $parts) -ge 2
            set keyring_key $parts[2]
        end
        set -l val (security find-generic-password -a $USER -s $keyring_key -w 2>/dev/null)
        if test -z "$val"
            echo "with-secret: '$keyring_key' not found in dev-secrets keychain" >&2
            return 1
        end
        if contains -- $keyring_key $multiline_keyring_keys
            if not string match -qr '^[[:xdigit:]]+$' -- "$val"
                echo "with-secret: multiline secret '$keyring_key' was not returned as hexadecimal data" >&2
                return 1
            end
            if test (math (string length -- "$val") % 2) -ne 0
                echo "with-secret: multiline secret '$keyring_key' had invalid hexadecimal data" >&2
                return 1
            end
            set val (printf '%s' "$val" | /usr/bin/xxd -r -p | string collect)
            if not string match -qr '\n' -- "$val"
                echo "with-secret: multiline secret '$keyring_key' did not decode to multiline text" >&2
                return 1
            end
        end
        set -fx $env_name $val
    end

    $rest
end
