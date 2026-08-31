# BB Auth

Noctalia authentication UI provider for [bb-auth](https://github.com/anthonyhab/bb-auth).

The plugin connects Noctalia to the bb-auth provider API and presents authentication requests using Noctalia's native declarative UI instead of the standalone bb-auth fallback window.

It supports authentication sessions handled by bb-auth, including **Polkit**, **pinentry/GPG-compatible clients**, and compatible **keyring** prompts.

## Plugin

| Field   | Value                                |
| ------- | ------------------------------------ |
| ID      | `branrgx/bb-auth`                    |
| Entries | Panel: `prompt`; service: `provider` |

## Requirements

The plugin requires:

* [bb-auth](https://github.com/anthonyhab/bb-auth)
* Python 3
* Noctalia v5 with plugin support

`bb-auth` must be installed and its user service must be running:

```sh
systemctl --user enable --now bb-auth.service
```

Check that the daemon is available with:

```sh
/usr/libexec/bb-auth --ping
```

### Polkit

bb-auth can act as the graphical Polkit authentication agent for the session.

Only one Polkit authentication agent can normally be registered for a session. If Noctalia's built-in Polkit agent or another authentication agent is enabled, disable it before using bb-auth as the Polkit agent.

If needed, bb-auth can be configured to warn instead of failing when it detects another authentication agent:

```ini
# ~/.config/systemd/user/bb-auth.service.d/override.conf

[Service]
Environment=BB_AUTH_CONFLICT_MODE=warn
```

Then reload and restart the service:

```sh
systemctl --user daemon-reload
systemctl --user restart bb-auth.service
```

### Pinentry

Applications using the pinentry protocol can use the bb-auth pinentry frontend.

For applications that allow configuring the pinentry executable, use:

```text
/usr/libexec/pinentry-bb
```

For example, with `rbw`:

```sh
rbw config set pinentry /usr/libexec/pinentry-bb
```

The plugin itself is not specific to `rbw`; any compatible pinentry client handled by bb-auth can use the same authentication UI.

## Usage

The plugin runs as a background Noctalia service.

When bb-auth creates an authentication session, the service receives the request and opens the authentication panel automatically.

The panel displays the requestor information supplied by bb-auth when available:

* application or requestor name;
* application icon;
* authentication state or error;
* password/input field;
* cancel and authenticate actions.

Press **Enter** to submit the current response.

Press **Escape** or **Cancel** to cancel the authentication session.

The panel can also be toggled manually with:

```sh
noctalia msg panel-toggle branrgx/bb-auth:prompt
```

Normally there is no reason to open it manually because authentication sessions open it automatically.

## How it works

The plugin consists of a Noctalia service, a declarative authentication panel and a small Python IPC bridge:

```text
Application
    │
    ├── Polkit
    ├── pinentry
    └── keyring
         │
         ▼
      bb-auth
         │
         │ Unix socket
         ▼
     bridge.py
         │
         ▼
    service.luau
         │
         ▼
     panel.luau
         │
         │ response / cancel
         ▼
      send.py
         │
         ▼
     bridge.py
         │
         ▼
      bb-auth
```

### `service.luau`

Runs as the Noctalia `provider` service.

It starts the IPC bridge, registers itself as a bb-auth UI provider, subscribes to authentication sessions and maintains the state consumed by the panel.

It handles:

* provider registration;
* provider heartbeat;
* `session.created`;
* `session.updated`;
* `session.closed`;
* authentication cancellation;
* panel opening;
* session lifecycle.

### `panel.luau`

Implements the authentication interface using Noctalia's declarative UI.

Secrets remain local to the panel and are not stored in Noctalia's shared plugin state.

### `bridge.py`

Maintains the connection between the plugin and bb-auth.

It connects to:

```text
$XDG_RUNTIME_DIR/bb-auth.sock
```

and registers the plugin as a custom UI provider.

The bridge also creates a local command socket:

```text
$XDG_RUNTIME_DIR/noctalia-bb-auth.sock
```

used for sending responses from the panel back to the active bb-auth provider connection.

### `send.py`

Sends panel responses and cancellation requests to the local bridge.

Authentication responses are not passed as command-line arguments. The panel writes the IPC payload to a temporary plugin data file, `send.py` reads and removes it, and then forwards the request through the local Unix socket.

## Provider behavior

The plugin registers with bb-auth using the provider name:

```text
noctalia-v5
```

with priority `100`.

It periodically sends heartbeats so bb-auth keeps the provider active.

When this provider is active, authentication requests are routed to Noctalia instead of the bb-auth standalone fallback UI.

If the provider disconnects or becomes unavailable, bb-auth remains responsible for its own fallback behavior.

## Requestor identity

Application names and icons shown by the panel come from the requestor information supplied by bb-auth.

Depending on how an authentication request originates, bb-auth may not always be able to identify the desktop application that ultimately caused it. Some requests can therefore appear under an intermediary process such as `systemd` and may not have an application icon.

When bb-auth provides a usable icon name, the plugin resolves it through Noctalia's application icon API.

The plugin intentionally does not maintain application-specific mappings such as replacing `systemd` with a particular application, since the same intermediary can represent authentication requests from many different programs.

## Pinentry behavior

A successful pinentry exchange does not necessarily mean that the requesting application accepted the supplied secret.

For example:

```text
Noctalia
    │
    │ password
    ▼
  bb-auth
    │
    ▼
 pinentry client
    │
    ├── accepted ──► continue
    │
    └── rejected ──► create another prompt
```

Because validation can happen after the pinentry conversation completes, the provider keeps a short grace period for successful pinentry sessions.

If the application immediately creates another authentication session, the new prompt is displayed normally with the updated error information.

This behavior applies to pinentry clients generally and is not specific to any individual password manager.

## Security

Authentication plugins handle sensitive input and should be treated accordingly.

This plugin:

* does not store passwords in Noctalia shared state;
* does not intentionally log authentication responses;
* does not pass passwords through process command-line arguments;
* communicates with bb-auth through Unix sockets in the user's runtime directory;
* restricts the local bridge command socket to the current user;
* removes temporary response files immediately after reading them.

The plugin is trusted, unsandboxed code and runs with the permissions of the current user, like other Noctalia plugins.

bb-auth is a separate component and is responsible for the authentication mechanisms and privileged operations it implements.

## Troubleshooting

Check the bb-auth service:

```sh
systemctl --user status bb-auth.service
```

Check that bb-auth responds:

```sh
/usr/libexec/bb-auth --ping
```

Check the sockets:

```sh
ls -l \
    "$XDG_RUNTIME_DIR/bb-auth.sock" \
    "$XDG_RUNTIME_DIR/noctalia-bb-auth.sock"
```

Check relevant session logs:

```sh
journalctl --user -b | grep -iE 'noctalia|bb-auth'
```

If Polkit authentication does not work, make sure another Polkit agent is not already registered for the same desktop session.

If pinentry applications still show another pinentry frontend, configure that application to use:

```text
/usr/libexec/pinentry-bb
```

## Notes

* The plugin is a **UI provider** for bb-auth; it does not implement Polkit, pinentry or keyring authentication itself.
* bb-auth must remain running for authentication requests to work.
* The panel opens automatically when an active authentication session requires user interaction.
* Requestor names and icons depend on the information bb-auth can determine for each authentication request.
* Polkit, pinentry and keyring have different session semantics; the provider handles them through the common bb-auth session protocol while preserving behavior required by each source.
* Noctalia's built-in Polkit agent should not be enabled at the same time when bb-auth is acting as the session's Polkit agent.

## License

MIT
