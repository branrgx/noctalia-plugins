# Noctalia Plugins

<p align="center">
  <img src="https://assets.noctalia.dev/noctalia-logo.svg?v=2" alt="Noctalia Logo" width="192" />
</p>

---

Personal plugin source for [Noctalia](https://github.com/noctalia-dev/noctalia).

This repository contains plugins I develop and maintain for my Noctalia setup. It follows the Noctalia v5 plugin source structure, allowing the repository to be added directly as a plugin source.

> [!NOTE]
> The Noctalia v5 plugin system is currently in beta. Plugin manifests and APIs may change as the plugin system evolves.

## Plugins

| Plugin                 | Description                                                                                                                                                        |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`bb-auth`](./bb-auth) | Authentication UI provider for [bb-auth](https://github.com/anthonyhab/bb-auth), integrating Polkit, pinentry and compatible keyring authentication with Noctalia. |

## Repository layout

Each plugin lives in its own top-level directory:

```text
noctalia-plugins/
├── bb-auth/
│   ├── plugin.toml
│   ├── service.luau
│   ├── panel.luau
│   ├── bridge.py
│   └── send.py
├── catalog.toml
├── .luaurc
├── .nvim.lua
└── README.md
```

Each plugin has its own `plugin.toml` manifest and uses the standard Noctalia plugin ID format:

```text
<author>/<plugin>
```

For example:

```text
branrgx/bb-auth
```

`catalog.toml` contains the plugin catalog exposed by this source.

## Installation

Add this repository as a Noctalia plugin source:

```sh
noctalia msg plugins source add branrgx https://github.com/branrgx/noctalia-plugins
```

Then enable the desired plugin:

```sh
noctalia msg plugins enable branrgx/bb-auth
```

For local development, add the checkout directly as a path source:

```sh
noctalia msg plugins source add dev path ~/Proyectos/noctalia-plugins
```

Then enable the plugin normally:

```sh
noctalia msg plugins enable branrgx/bb-auth
```

`.luau` changes support hot reload. Changes to `plugin.toml` may require a Noctalia configuration reload.

## Development

Plugins are written for the Noctalia v5 plugin system using `plugin.toml` manifests and Luau entry scripts.

The Noctalia documentation is the primary reference:

* [Plugin development](https://docs.noctalia.dev/noctalia/plugins/development/)
* [Manifest](https://docs.noctalia.dev/noctalia/plugins/development/manifest/)
* [Entry types](https://docs.noctalia.dev/noctalia/plugins/development/entries/)
* [Declarative UI](https://docs.noctalia.dev/noctalia/plugins/development/declarative-ui/)
* [Runtime API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/)
* [Development workflow](https://docs.noctalia.dev/noctalia/plugins/development/workflow/)

The official repositories are also useful references:

* [Official plugins](https://github.com/noctalia-dev/official-plugins)
* [Community plugins](https://github.com/noctalia-dev/community-plugins)

### Editor support

[`noctalia.d.luau`](https://github.com/noctalia-dev/official-plugins/blob/main/noctalia.d.luau) provides the Noctalia plugin API definitions for `luau-lsp`.

It can be downloaded into the repository root with:

```sh
curl -O https://raw.githubusercontent.com/noctalia-dev/official-plugins/main/noctalia.d.luau
```

The local definition file can be excluded from Git and referenced by the editor/Luau LSP configuration.

This repository includes:

```text
.luaurc
.nvim.lua
```

for local Luau and Neovim development configuration.

## Security

Noctalia plugins are trusted, unsandboxed Luau code.

Depending on their purpose, plugins may execute processes, access files, communicate through IPC or interact with other services running in the user session.

Plugins in this repository keep external dependencies and system interactions explicit in their manifests and documentation.

Authentication-related plugins must not intentionally persist or log authentication secrets.

## License

Each plugin defines its own license through its `plugin.toml` manifest and may include an individual `LICENSE` file when necessary.

Noctalia and third-party dependencies remain subject to their respective licenses.
