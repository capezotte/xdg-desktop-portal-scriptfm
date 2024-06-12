# xdg-desktop-portal-scriptfm

An xdg-desktop-portal portal backend that lets you open files with a custom file chooser instead of a GUI toolkit's bundled one.

Inspired by [xdg-desktop-portal-termfilechooser](https://github.com/GermainZ/xdg-desktop-portal-termfilechooser) (called from now on `xdp-tfc`).

# Requirements

- Vala 0.56

# Building

```sh
make VALAC=valac
```

# Installing

```sh
make DESTDIR=... PREFIX=/usr LIBEXECDIR=/usr/libexec install
```

Note that some distributions expect `LIBEXECDIR=/usr/lib` (like Arch Linux).

# Configuration

`scriptfm` is configured using environment variables. So far it only uses `SFM_FILE_SCRIPT`, which must be the path to the script.

For instance, you run upon starting your window manager:

```
SFM_FILE_SCRIPT=~/.scripts/my-file-manager scriptfm
```

If you want to rely on D-Bus activation, you'd want to `dbus-update-activation-environment SFM_FILE_SCRIPT=xyzzy` (where `xyzzy` is the path to your script).

# Your script

Scripts receive four environment variables. They are 1 if true, empty if false:

- `SFM_MULTIPLE`: multiple files should be selected.
- `SFM_DIRECTORY`: a directory must be selected.
- `SFM_SAVE`: we want to save a file.
- `SFM_PATH`: the path to write to, suggested by the program.

**Unlike xdp-tfc**, xdp-sfm expects filenames to come out NUL-terminated in stdout. This is somewhat more complex to script, but (a) alows us to handle weird filenames that are nonetheless allowed (b) many terminal file managers can work with this format (it's even the default output format of `lf` and `nnn`, for instance). See `contrib/lf` for an example.

# TODO

- Encode the additional information xdg-desktop-portal gives us (for example, the globs expected by the program).
- Support AppChooser too.
