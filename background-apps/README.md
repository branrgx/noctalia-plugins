# Background Apps

A Noctalia plugin that displays applications running in the background.

## Features

- Shows background applications directly in the Noctalia bar.
- Hides automatically when no background applications are running.
- Uses application icons from desktop entries.
- Left click activates an application.
- Stop requests a graceful shutdown.
- Force Stop terminates the Flatpak application.

## Requirements

- Noctalia
- xdg-desktop-portal
- A working org.freedesktop.background.Monitor implementation
- gdbus
- flatpak
