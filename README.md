# vscode-nix

A Nix flake that packages VS Code (Microsoft's official build) directly from binaries, with automated daily updates, Cachix binary caching, and declarative configuration for extensions, settings, and keybindings.

## Features

- Official Microsoft VS Code binaries (not VSCodium)
- Supports Linux x64, Linux aarch64, macOS x64, and macOS aarch64
- Automated daily updates via GitHub Actions
- Pre-built binaries on Cachix for instant installation
- Declarative extensions management
- Settings and keybindings configuration via Nix
- Smart Home Manager integration detection

## Quick Start

```bash
# Run VS Code directly (no installation needed)
nix run github:dominicnunez/vscode-nix

# Or try it in a temporary shell
nix shell github:dominicnunez/vscode-nix -c code
```

## Cachix Setup

Pre-built binaries are available via Cachix for instant installation without local compilation.

### NixOS Configuration

```nix
# configuration.nix or in your NixOS module
nix.settings = {
  substituters = [ "https://vscode-nix.cachix.org" ];
  trusted-public-keys = [ "vscode-nix.cachix.org-1:JkWxvwZs0Mb/lp48seQIqOGU4MbwD2Mn9Mm4tZp7K48=" ];
};
```

### Non-NixOS (nix.conf)

Add to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`:

```
substituters = https://cache.nixos.org https://vscode-nix.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= vscode-nix.cachix.org-1:JkWxvwZs0Mb/lp48seQIqOGU4MbwD2Mn9Mm4tZp7K48=
```

### Flake-based Setup

```nix
{
  nixConfig = {
    extra-substituters = [ "https://vscode-nix.cachix.org" ];
    extra-trusted-public-keys = [ "vscode-nix.cachix.org-1:JkWxvwZs0Mb/lp48seQIqOGU4MbwD2Mn9Mm4tZp7K48=" ];
  };
}
```

## Installation

### As a Flake Input

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    vscode-nix.url = "github:dominicnunez/vscode-nix";
  };

  outputs = { self, nixpkgs, vscode-nix, ... }: {
    # NixOS system configuration
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            vscode-nix.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

### With Home Manager (Flake)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    vscode-nix.url = "github:dominicnunez/vscode-nix";
  };

  outputs = { self, nixpkgs, home-manager, vscode-nix, ... }: {
    homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        ({ pkgs, ... }: {
          home.packages = [
            vscode-nix.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

### Using the Overlay

```nix
{
  inputs.vscode-nix.url = "github:dominicnunez/vscode-nix";

  outputs = { self, nixpkgs, vscode-nix }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nixpkgs.overlays = [ vscode-nix.overlays.default ];
          environment.systemPackages = [ pkgs.vscode-nix ];
        }
      ];
    };
  };
}
```

## Extensions Configuration

### Using vscodeWithExtensions

The `lib.vscodeWithExtensions` function creates a VS Code derivation with extensions pre-configured. The second argument accepts a settings attrset, or an attrset with `settings` and `keybindings` when you want both:

```nix
{
  inputs.vscode-nix.url = "github:dominicnunez/vscode-nix";

  outputs = { self, nixpkgs, vscode-nix }: {
    packages.x86_64-linux.my-vscode = vscode-nix.lib.x86_64-linux.vscodeWithExtensions
      # Extensions list
      [
        "ms-python.python"
        "esbenp.prettier-vscode"
        "dbaeumer.vscode-eslint"
        "ms-vscode.cpptools@1.20.0"  # Pin specific version
      ]
      # Settings and keybindings (optional)
      {
        settings = null;
        keybindings = null;
      };
  };
}
```

### Direct Package Configuration

You can also configure extensions directly when calling the package:

```nix
vscode-nix.packages.${system}.default.override {
  extensions = [
    "ms-python.python"
    "esbenp.prettier-vscode@10.0.0"  # Pinned version
  ];
}
```

Extensions are:
- Installed on first run via VS Code's `--install-extension` command
- Stored in `~/.local/share/vscode-nix/extensions` (persists across updates)
- Only reinstalled when the extension list changes

## Settings Configuration

Provide VS Code settings as a Nix attribute set:

```nix
{
  packages.x86_64-linux.my-vscode = vscode-nix.lib.x86_64-linux.vscodeWithExtensions
    [ "ms-python.python" ]
    # Settings
    {
      "editor.fontSize" = 14;
      "editor.tabSize" = 2;
      "editor.formatOnSave" = true;
      "workbench.colorTheme" = "One Dark Pro";
      "files.autoSave" = "afterDelay";
      "python.languageServer" = "Pylance";
    };
}
```

Or using `override`:

```nix
vscode-nix.packages.${system}.default.override {
  userSettings = {
    "editor.fontSize" = 14;
    "editor.minimap.enabled" = false;
  };
}
```

Settings behavior:
- Nix settings are used as defaults on first run
- User modifications in VS Code are preserved and take precedence
- If Nix settings change, they are merged with user settings (user wins on conflicts)
- Settings stored in `~/.local/share/vscode-nix/user-data/User/settings.json`

## Keybindings Configuration

Provide custom keybindings as a list of attribute sets:

```nix
{
  packages.x86_64-linux.my-vscode = vscode-nix.lib.x86_64-linux.vscodeWithExtensions
    [ "ms-python.python" ]
    {
      settings = { "editor.fontSize" = 14; };
      # Keybindings
      keybindings = [
        { key = "ctrl+k ctrl+t"; command = "workbench.action.terminal.focus"; }
        { key = "ctrl+k ctrl+e"; command = "workbench.action.focusActiveEditorGroup"; }
        { key = "ctrl+shift+d"; command = "editor.action.duplicateSelection"; }
        {
          key = "ctrl+shift+/";
          command = "editor.action.blockComment";
          when = "editorTextFocus";
        }
      ];
    };
}
```

Or using `override`:

```nix
vscode-nix.packages.${system}.default.override {
  userKeybindings = [
    { key = "ctrl+k ctrl+t"; command = "workbench.action.terminal.focus"; }
  ];
}
```

Keybindings behavior:
- Nix keybindings are added as defaults on first run
- User modifications in VS Code are preserved
- If Nix keybindings change, they are merged (user keybindings take precedence)
- Duplicate keybindings are deduped by `key`, keeping the user entry
- Keybindings stored in `~/.local/share/vscode-nix/user-data/User/keybindings.json`

## Full Configuration Example

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    vscode-nix.url = "github:dominicnunez/vscode-nix";
  };

  outputs = { self, nixpkgs, vscode-nix }: {
    packages.x86_64-linux.my-dev-environment =
      vscode-nix.lib.x86_64-linux.vscodeWithExtensions
        # Extensions
        [
          # Python development
          "ms-python.python"
          "ms-python.vscode-pylance"
 
          # JavaScript/TypeScript
          "esbenp.prettier-vscode"
          "dbaeumer.vscode-eslint"
 
          # Git
          "eamodio.gitlens"
 
          # Nix
          "jnoortheen.nix-ide"
 
          # Theme
          "zhuangtongfa.material-theme"
        ]
        {
          # Settings
          settings = {
            # Editor
            "editor.fontSize" = 13;
            "editor.fontFamily" = "'JetBrains Mono', 'Fira Code', monospace";
            "editor.fontLigatures" = true;
            "editor.tabSize" = 2;
            "editor.formatOnSave" = true;
            "editor.minimap.enabled" = false;
 
            # Files
            "files.autoSave" = "afterDelay";
            "files.trimTrailingWhitespace" = true;
 
            # Theme
            "workbench.colorTheme" = "One Dark Pro";
            "workbench.iconTheme" = "material-icon-theme";
 
            # Terminal
            "terminal.integrated.fontSize" = 12;
 
            # Python
            "python.languageServer" = "Pylance";
 
            # Nix
            "nix.enableLanguageServer" = true;
          };
          # Keybindings
          keybindings = [
            { key = "ctrl+k ctrl+t"; command = "workbench.action.terminal.focus"; }
            { key = "ctrl+k ctrl+e"; command = "workbench.action.focusActiveEditorGroup"; }
          ];
        };
  };
}
```

## Home Manager Integration

This package includes smart Home Manager detection. When running VS Code:

**If Home Manager is detected:**
- Skips creating `~/.local/bin/code` symlink
- Respects your declarative Home Manager configuration
- Prints informational message (suppressible)

**If Home Manager is NOT detected:**
- Creates `~/.local/bin/code` symlink for convenience
- Allows running `code` from anywhere if `~/.local/bin` is in your PATH

### Detection Indicators

Home Manager is detected if any of these conditions are true:
- `HM_SESSION_VARS` environment variable is set
- `~/.config/home-manager` directory exists
- `/etc/profiles/per-user/$USER` directory exists

### Suppressing Messages

To suppress informational messages from the wrapper:

```bash
export VSCODE_NIX_QUIET=1
```

Or add to your shell profile:

```bash
# ~/.bashrc or ~/.zshrc
export VSCODE_NIX_QUIET=1
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VSCODE_NIX_QUIET` | Set to `1` to suppress wrapper messages | unset |
| `XDG_DATA_HOME` | Base directory for VS Code data | `~/.local/share` |
| `XDG_CONFIG_HOME` | Base directory for VS Code config | `~/.config` |

## Data Directories

When using extensions, settings, or keybindings configuration:

| Path | Purpose |
|------|---------|
| `~/.local/share/vscode-nix/extensions` | Installed extensions |
| `~/.local/share/vscode-nix/user-data` | User settings, keybindings, state |

## Contributing

### How Updates Work

1. **Daily Check**: GitHub Actions runs `update.sh` daily at 00:00 UTC
2. **Version Detection**: Script queries GitHub API for latest VS Code release
3. **Hash Fetching**: If newer version found, fetches SHA256 hashes for all platforms
4. **PR Creation**: Creates PR with updated `version.json`
5. **CI Validation**: PR triggers build on Linux and macOS to verify package works
6. **Auto-Merge**: After CI passes, PR is automatically squash-merged

### Manual Update

To manually trigger an update check:

1. Go to Actions tab in GitHub
2. Select "Update VS Code" workflow
3. Click "Run workflow"

### Local Development

```bash
# Enter development shell
nix develop

# Check for updates (dry run)
./update.sh

# Check and apply update
./update.sh --update

# Build the package
nix build

# Run the built package
nix run

# Run flake checks
nix flake check
```

### Repository Structure

```
.
├── flake.nix           # Flake definition with outputs
├── flake.lock          # Locked dependencies
├── package.nix         # VS Code package derivation
├── version.json        # Current version and platform hashes
├── update.sh           # Update detection and hash fetching script
├── README.md           # This file
└── .github/workflows/
    ├── update.yml      # Daily update check workflow
    ├── ci.yml          # PR build validation workflow
    └── cachix.yml      # Binary cache push workflow
```

## License

VS Code is proprietary software from Microsoft. This flake packages the official binaries. See [VS Code License](https://code.visualstudio.com/license) for terms.

The Nix packaging code in this repository is MIT licensed.
