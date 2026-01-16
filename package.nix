{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  writeText,
  writeTextFile,
  runCommandLocal,
  # Optional: list of extension IDs to install (e.g., ["ms-python.python" "esbenp.prettier-vscode@10.0.0"])
  extensions ? [ ],
  # Optional: user settings attrset (e.g., { "editor.fontSize" = 14; })
  userSettings ? null,
  # Optional: user keybindings list (e.g., [{ key = "ctrl+k"; command = "workbench.action.terminal.focus"; }])
  userKeybindings ? null,
  # Linux dependencies
  gtk3,
  glib,
  nss,
  nspr,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cups,
  dbus,
  expat,
  libdrm,
  libxkbcommon,
  mesa,
  pango,
  cairo,
  alsa-lib,
  xorg,
  libsecret,
  libnotify,
  systemd,
  # Additional runtime dependencies for full functionality
  xdg-utils,
  krb5,
  libglvnd,
  wayland,
  libpulseaudio,
  libva,
  ffmpeg,
  e2fsprogs,
  util-linux,
  coreutils,
  gnused,
  gnugrep,
  git,
  jq,
  # Microsoft authentication runtime dependencies
  webkitgtk_4_1,
  libsoup_3,
  # macOS dependencies
  unzip,
}:

let
  versionData = lib.importJSON ./version.json;
  version = versionData.version;
  hashes = versionData.hashes;

  # Platform-specific configuration
  platformConfig = {
    x86_64-linux = {
      platform = "linux-x64";
      archive = "tar.gz";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      archive = "tar.gz";
    };
    x86_64-darwin = {
      platform = "darwin";
      archive = "zip";
    };
    aarch64-darwin = {
      platform = "darwin-arm64";
      archive = "zip";
    };
  };

  system = stdenv.hostPlatform.system;
  config = platformConfig.${system} or (throw "Unsupported system: ${system}");
  hash = hashes.${system} or (throw "No hash for system: ${system}");

  src = fetchurl {
    url = "https://update.code.visualstudio.com/${version}/${config.platform}/stable";
    inherit hash;
  };

  # Write extensions list to file if extensions are specified
  extensionsList =
    if extensions != [ ] then
      writeText "vscode-extensions.txt" (lib.concatStringsSep "\n" extensions)
    else
      null;

  # Write settings.json to Nix store if userSettings is provided
  # This serves as default settings; user modifications at runtime take precedence
  settingsJson =
    if userSettings != null then
      writeText "vscode-settings.json" (builtins.toJSON userSettings)
    else
      null;

  # Write keybindings.json to Nix store if userKeybindings is provided
  # Keybindings are a JSON array of objects with key, command, and optional when
  keybindingsJson =
    if userKeybindings != null then
      writeText "vscode-keybindings.json" (builtins.toJSON userKeybindings)
    else
      null;

  # Shared wrapper script template for both Linux and macOS
  # Placeholders:
  #   VSCODE_BIN_PLACEHOLDER - path to the actual VS Code binary
  #   EXTRA_PATH_PLACEHOLDER - additional PATH entries for runtime deps
  #   EXTRA_LD_LIBRARY_PATH_PLACEHOLDER - additional LD_LIBRARY_PATH entries (Linux-only, empty on macOS)
  #   EXTENSIONS_LIST_PLACEHOLDER - path to extensions list file
  #   NIX_SETTINGS_JSON_PLACEHOLDER - path to settings.json in Nix store
  #   NIX_KEYBINDINGS_JSON_PLACEHOLDER - path to keybindings.json in Nix store
  sharedWrapperScript = ''
                #!/usr/bin/env bash
                set -euo pipefail

                # Home Manager detection function
                is_home_manager_active() {
                  # Check HM_SESSION_VARS environment variable
                  [[ -n "''${HM_SESSION_VARS:-}" ]] && return 0

                  # Check for Home Manager config directory
                  [[ -d "$HOME/.config/home-manager" ]] && return 0

                  # Check for per-user profile (NixOS Home Manager indicator)
                  [[ -d "/etc/profiles/per-user/$USER" ]] && return 0

                  return 1
                }

                # Manage ~/.local/bin/code symlink based on Home Manager detection
                manage_symlink() {
                  local target_dir="$HOME/.local/bin"
                  local symlink_path="$target_dir/code"
                  local real_code="VSCODE_BIN_PLACEHOLDER"

                  # Check if user wants verbose output (quiet by default)
                  local verbose=''${VSCODE_NIX_VERBOSE:-0}

                  if is_home_manager_active; then
                    # Home Manager detected - skip symlink creation
                    if [[ "$verbose" == "1" ]]; then
                      echo "[vscode-nix] Home Manager detected - skipping ~/.local/bin/code symlink" >&2
                    fi

                    # Remove our symlink if it exists and points to our binary
                    if [[ -L "$symlink_path" ]]; then
                      local current_target
                      current_target=$(realpath "$symlink_path" 2>/dev/null || readlink "$symlink_path" 2>/dev/null || true)
                      if [[ "$current_target" == "$real_code" ]]; then
                        rm -f "$symlink_path"
                        if [[ "$verbose" == "1" ]]; then
                          echo "[vscode-nix] Removed existing symlink (was managed by vscode-nix)" >&2
                        fi
                      fi
                    fi
                  else
                    # Home Manager not detected - create symlink for convenience
                    if [[ ! -d "$target_dir" ]]; then
                      mkdir -p "$target_dir"
                    fi

                    # Only create/update symlink if it doesn't exist or points elsewhere
                    if [[ ! -e "$symlink_path" ]] || [[ -L "$symlink_path" ]]; then
                      local needs_update=0

                      if [[ ! -e "$symlink_path" ]]; then
                        needs_update=1
                      elif [[ -L "$symlink_path" ]]; then
                        local current_target
                        current_target=$(realpath "$symlink_path" 2>/dev/null || readlink "$symlink_path" 2>/dev/null || true)
                        if [[ "$current_target" != "$real_code" ]]; then
                          needs_update=1
                        fi
                      fi

                      if [[ "$needs_update" == "1" ]]; then
                        ln -sf "$real_code" "$symlink_path"
                        if [[ "$verbose" == "1" ]]; then
                          echo "[vscode-nix] Created ~/.local/bin/code symlink" >&2
                        fi
                      fi
                    fi
                  fi
                }

                # Set up environment
                export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
                export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
                export PATH="EXTRA_PATH_PLACEHOLDER:$PATH"

                # State-based symlink management
                # Only run when binary path or HM detection status changes
                SYMLINK_STATE_FILE="''${XDG_DATA_HOME}/vscode-nix/.symlink-state"
                CURRENT_BINARY="VSCODE_BIN_PLACEHOLDER"

                # Determine current HM status
                if is_home_manager_active; then
                  CURRENT_HM_DETECTED="true"
                else
                  CURRENT_HM_DETECTED="false"
                fi

                # Check if state has changed
                run_symlink_management=0
                if [[ ! -f "$SYMLINK_STATE_FILE" ]]; then
                  run_symlink_management=1
                else
                  # Read stored state
                  stored_binary=""
                  stored_hm=""
                  while IFS='=' read -r key value; do
                    case "$key" in
                      BINARY_PATH) stored_binary="$value" ;;
                      HM_DETECTED) stored_hm="$value" ;;
                    esac
                  done < "$SYMLINK_STATE_FILE"

                  # Compare with current state
                  if [[ "$stored_binary" != "$CURRENT_BINARY" ]] || [[ "$stored_hm" != "$CURRENT_HM_DETECTED" ]]; then
                    run_symlink_management=1
                  fi
                fi

                if [[ "$run_symlink_management" == "1" ]]; then
                  manage_symlink

                  # Update state file
                  mkdir -p "$(dirname "$SYMLINK_STATE_FILE")"
                  printf "BINARY_PATH=%s\nHM_DETECTED=%s\n" "$CURRENT_BINARY" "$CURRENT_HM_DETECTED" > "$SYMLINK_STATE_FILE"
                fi

                # Set LD_LIBRARY_PATH for Linux (empty/harmless on macOS)
                if [[ -n "EXTRA_LD_LIBRARY_PATH_PLACEHOLDER" ]]; then
                  export LD_LIBRARY_PATH="EXTRA_LD_LIBRARY_PATH_PLACEHOLDER:''${LD_LIBRARY_PATH:-}"
                fi

                # Extensions management
                EXTENSIONS_DIR="''${XDG_DATA_HOME}/vscode-nix/extensions"
                EXTENSIONS_LIST="EXTENSIONS_LIST_PLACEHOLDER"
                EXTENSIONS_MARKER="''${XDG_DATA_HOME}/vscode-nix/.extensions-installed"

                # Settings management
                # NIX_SETTINGS_JSON points to read-only settings in Nix store
                # User data dir is mutable so users can modify settings in VS Code
                NIX_SETTINGS_JSON="NIX_SETTINGS_JSON_PLACEHOLDER"
                NIX_KEYBINDINGS_JSON="NIX_KEYBINDINGS_JSON_PLACEHOLDER"
                USER_DATA_DIR="''${XDG_DATA_HOME}/vscode-nix/user-data"
                SETTINGS_MARKER="''${USER_DATA_DIR}/.settings-initialized"
                KEYBINDINGS_MARKER="''${USER_DATA_DIR}/.keybindings-initialized"

                # Cross-platform md5 hash function (handles both Linux md5sum and macOS md5)
                compute_md5() {
                  local file="$1"
                  if command -v md5sum &>/dev/null; then
                    md5sum "$file" 2>/dev/null | cut -d' ' -f1
                  elif command -v md5 &>/dev/null; then
                    md5 -q "$file" 2>/dev/null
                  else
                    echo ""
                  fi
                }

                # Initialize settings from Nix-provided defaults (one-time operation)
                # User can modify settings in VS Code; those changes persist and take precedence
                initialize_settings() {
                  if [[ "$NIX_SETTINGS_JSON" != "" ]] && [[ -f "$NIX_SETTINGS_JSON" ]]; then
                    local settings_dir="''${USER_DATA_DIR}/User"

                    # Only initialize if marker doesn't exist or Nix settings have changed
                local settings_hash
                settings_hash=$(compute_md5 "$NIX_SETTINGS_JSON")

                if [[ ! -f "$SETTINGS_MARKER" ]] || [[ "$(cat "$SETTINGS_MARKER" 2>/dev/null)" != "$settings_hash" ]]; then
                  mkdir -p "$settings_dir"
                  mkdir -p "$(dirname "$SETTINGS_MARKER")"

                  local verbose=''${VSCODE_NIX_VERBOSE:-0}
                  if [[ "$verbose" == "1" ]]; then
                    echo "[vscode-nix] Initializing settings from Nix configuration..." >&2
                  fi

                  # If user has existing settings, merge Nix settings as defaults (user takes precedence)
                  if [[ -f "''${settings_dir}/settings.json" ]]; then
                    # Use jq to merge if available, otherwise just use user settings
                    if command -v jq &>/dev/null; then
                      # Merge: Nix settings as base, user settings override
                      local tmp_settings
                      tmp_settings=$(mktemp)
                      jq -s '.[0] * .[1]' "$NIX_SETTINGS_JSON" "''${settings_dir}/settings.json" > "$tmp_settings" 2>/dev/null && \
                        mv "$tmp_settings" "''${settings_dir}/settings.json" || rm -f "$tmp_settings"
                      if [[ "$verbose" == "1" ]]; then
                        echo "[vscode-nix] Merged Nix defaults with existing user settings" >&2
                      fi
                    else
                      if [[ "$verbose" == "1" ]]; then
                        echo "[vscode-nix] jq not found; keeping existing user settings" >&2
                      fi
                    fi
                  else
                    # No existing settings; copy Nix settings as starting point
                    cp "$NIX_SETTINGS_JSON" "''${settings_dir}/settings.json"
                    if [[ "$verbose" == "1" ]]; then
                      echo "[vscode-nix] Copied Nix settings as defaults" >&2
                    fi
                  fi

                  # Save hash to marker file
                  echo "$settings_hash" > "$SETTINGS_MARKER"
                fi
              fi
            }

                # Initialize keybindings from Nix-provided defaults (one-time operation)
                # User can modify keybindings in VS Code; those changes persist and take precedence
                initialize_keybindings() {
                  if [[ "$NIX_KEYBINDINGS_JSON" != "" ]] && [[ -f "$NIX_KEYBINDINGS_JSON" ]]; then
                    local keybindings_dir="''${USER_DATA_DIR}/User"

                    # Only initialize if marker doesn't exist or Nix keybindings have changed
            local keybindings_hash
            keybindings_hash=$(compute_md5 "$NIX_KEYBINDINGS_JSON")

            if [[ ! -f "$KEYBINDINGS_MARKER" ]] || [[ "$(cat "$KEYBINDINGS_MARKER" 2>/dev/null)" != "$keybindings_hash" ]]; then
              mkdir -p "$keybindings_dir"
              mkdir -p "$(dirname "$KEYBINDINGS_MARKER")"

              local verbose=''${VSCODE_NIX_VERBOSE:-0}
              if [[ "$verbose" == "1" ]]; then
                echo "[vscode-nix] Initializing keybindings from Nix configuration..." >&2
              fi

              # If user has existing keybindings, merge Nix keybindings as defaults (user takes precedence)
              if [[ -f "''${keybindings_dir}/keybindings.json" ]]; then
                # Use jq to merge if available, otherwise just use user keybindings
                if command -v jq &>/dev/null; then
                  # Merge: dedupe by key, prefer user keybindings on conflict
                  local tmp_keybindings
                  tmp_keybindings=$(mktemp)
                  jq -s '.[1] + .[0] | reduce .[] as $item ({seen: {}, result: []}; if (.seen[$item.key] // false) then . else .seen[$item.key] = true | .result += [$item] end) | .result' "$NIX_KEYBINDINGS_JSON" "''${keybindings_dir}/keybindings.json" > "$tmp_keybindings" 2>/dev/null && \
                    mv "$tmp_keybindings" "''${keybindings_dir}/keybindings.json" || rm -f "$tmp_keybindings"
                  if [[ "$verbose" == "1" ]]; then
                    echo "[vscode-nix] Merged Nix defaults with existing user keybindings" >&2
                  fi
                else
                  if [[ "$verbose" == "1" ]]; then
                    echo "[vscode-nix] jq not found; keeping existing user keybindings" >&2
                  fi
                fi
              else
                # No existing keybindings; copy Nix keybindings as starting point
                cp "$NIX_KEYBINDINGS_JSON" "''${keybindings_dir}/keybindings.json"
                if [[ "$verbose" == "1" ]]; then
                  echo "[vscode-nix] Copied Nix keybindings as defaults" >&2
                fi
              fi

              # Save hash to marker file
              echo "$keybindings_hash" > "$KEYBINDINGS_MARKER"
            fi
          fi
        }

                install_extensions() {
                  if [[ "$EXTENSIONS_LIST" != "" ]] && [[ -f "$EXTENSIONS_LIST" ]]; then
                    # Check if extensions need to be installed (first run or list changed)
                    local list_hash
                    list_hash=$(compute_md5 "$EXTENSIONS_LIST")

        if [[ ! -f "$EXTENSIONS_MARKER" ]] || [[ "$(cat "$EXTENSIONS_MARKER" 2>/dev/null)" != "$list_hash" ]]; then
          mkdir -p "$EXTENSIONS_DIR"
          mkdir -p "$(dirname "$EXTENSIONS_MARKER")"

          local verbose=''${VSCODE_NIX_VERBOSE:-0}
          if [[ "$verbose" == "1" ]]; then
            echo "[vscode-nix] Installing extensions..." >&2
          fi

          while IFS= read -r extension || [[ -n "$extension" ]]; do
            # Skip empty lines
            [[ -z "$extension" ]] && continue

            if [[ "$verbose" == "1" ]]; then
              echo "[vscode-nix] Installing: $extension" >&2
            fi

            # Install extension (supports publisher.name or publisher.name@version format)
            "VSCODE_BIN_PLACEHOLDER" --extensions-dir "$EXTENSIONS_DIR" --install-extension "$extension" --force 2>/dev/null || {
              if [[ "$verbose" == "1" ]]; then
                echo "[vscode-nix] Warning: Failed to install $extension" >&2
              fi
            }
          done < "$EXTENSIONS_LIST"

          # Save hash to marker file
          echo "$list_hash" > "$EXTENSIONS_MARKER"

          if [[ "$verbose" == "1" ]]; then
            echo "[vscode-nix] Extensions installation complete" >&2
          fi
        fi
      fi
    }

                # Run settings initialization if settings are provided
                initialize_settings

                # Run keybindings initialization if keybindings are provided
                initialize_keybindings

                # Run extension installation if list is provided
                install_extensions

                # Build command arguments
                VSCODE_ARGS=()

                # Add extensions-dir if extensions are configured
                if [[ "$EXTENSIONS_LIST" != "" ]] && [[ -f "$EXTENSIONS_LIST" ]]; then
                  VSCODE_ARGS+=(--extensions-dir "$EXTENSIONS_DIR")
                fi

                # Add user-data-dir if settings or keybindings are configured
                if [[ "$NIX_SETTINGS_JSON" != "" ]] && [[ -f "$NIX_SETTINGS_JSON" ]]; then
                  VSCODE_ARGS+=(--user-data-dir "$USER_DATA_DIR")
                elif [[ "$NIX_KEYBINDINGS_JSON" != "" ]] && [[ -f "$NIX_KEYBINDINGS_JSON" ]]; then
                  VSCODE_ARGS+=(--user-data-dir "$USER_DATA_DIR")
                fi

                exec "VSCODE_BIN_PLACEHOLDER" "''${VSCODE_ARGS[@]}" "$@"
  '';

  # Linux-specific derivation
  linuxPackage = stdenv.mkDerivation {
    pname = "vscode";
    inherit version src;

    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
      wrapGAppsHook3
    ];

    buildInputs = [
      # GTK and UI
      gtk3
      glib
      pango
      cairo
      atk
      at-spi2-atk
      at-spi2-core

      # Electron/Chromium dependencies
      nss
      nspr
      cups
      dbus
      expat
      libdrm
      libxkbcommon
      mesa
      libglvnd
      alsa-lib

      # X11 libraries
      xorg.libX11
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libXtst
      xorg.libxcb
      xorg.libxkbfile

      # Security and credentials
      libsecret
      krb5

      # Notifications
      libnotify

      # System services
      systemd

      # Wayland support
      wayland

      # Audio
      libpulseaudio

      # Video/hardware acceleration
      libva
      ffmpeg

      # Microsoft authentication (MSAL)
      webkitgtk_4_1
      libsoup_3
    ];

    # Runtime dependencies that need to be in PATH
    runtimeDependencies = [
      systemd
    ];

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      tar xzf $src
      runHook postUnpack
    '';

    installPhase = ''
            runHook preInstall

            mkdir -p $out/lib/vscode $out/bin
            cp -r VSCode-linux-*/* $out/lib/vscode/

            # Write shared wrapper script template
            cat > $out/bin/code << 'WRAPPER_EOF'
      ${sharedWrapperScript}
      WRAPPER_EOF

            # Replace placeholders with actual paths
            substituteInPlace $out/bin/code \
              --replace-fail "VSCODE_BIN_PLACEHOLDER" "$out/lib/vscode/bin/code" \
              --replace-fail "EXTRA_PATH_PLACEHOLDER" "${
                lib.makeBinPath [
                  xdg-utils # For opening URLs/files externally
                  git # For Git integration
                  coreutils # Basic utilities
                  gnused # sed for terminal
                  gnugrep # grep for search
                  e2fsprogs # Filesystem utilities
                  util-linux # System utilities
                  jq # For settings/keybindings JSON merge
                ]
              }" \
              --replace-fail "EXTRA_LD_LIBRARY_PATH_PLACEHOLDER" "${
                lib.makeLibraryPath [
                  libpulseaudio # Audio support
                  libva # Hardware video acceleration
                  wayland # Wayland support
                  libglvnd # OpenGL support
                ]
              }" \
              --replace-fail "EXTENSIONS_LIST_PLACEHOLDER" "${
                if extensionsList != null then extensionsList else ""
              }" \
              --replace-fail "NIX_SETTINGS_JSON_PLACEHOLDER" "${
                if settingsJson != null then settingsJson else ""
              }" \
              --replace-fail "NIX_KEYBINDINGS_JSON_PLACEHOLDER" "${
                if keybindingsJson != null then keybindingsJson else ""
              }"

            chmod +x $out/bin/code

            runHook postInstall
    '';

    meta = with lib; {
      description = "Visual Studio Code - Microsoft's official build";
      homepage = "https://code.visualstudio.com/";
      license = licenses.unfree;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mainProgram = "code";
    };
  };

  # macOS-specific derivation
  darwinPackage = stdenv.mkDerivation {
    pname = "vscode";
    inherit version src;

    nativeBuildInputs = [
      unzip
      makeWrapper
      jq # For settings/keybindings JSON merge
    ];

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      unzip -q $src
      runHook postUnpack
    '';

    installPhase = ''
            runHook preInstall

            mkdir -p $out/Applications $out/bin

            # Copy the app bundle
            cp -r "Visual Studio Code.app" $out/Applications/

            # Write shared wrapper script template
            cat > $out/bin/code << 'WRAPPER_EOF'
      ${sharedWrapperScript}
      WRAPPER_EOF

            # Replace placeholders with actual paths (macOS-specific values)
            substituteInPlace $out/bin/code \
              --replace-fail "VSCODE_BIN_PLACEHOLDER" "$out/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
              --replace-fail "EXTRA_PATH_PLACEHOLDER" "${lib.makeBinPath [ jq ]}" \
              --replace-fail "EXTRA_LD_LIBRARY_PATH_PLACEHOLDER" "" \
              --replace-fail "EXTENSIONS_LIST_PLACEHOLDER" "${
                if extensionsList != null then extensionsList else ""
              }" \
              --replace-fail "NIX_SETTINGS_JSON_PLACEHOLDER" "${
                if settingsJson != null then settingsJson else ""
              }" \
              --replace-fail "NIX_KEYBINDINGS_JSON_PLACEHOLDER" "${
                if keybindingsJson != null then keybindingsJson else ""
              }"

            chmod +x $out/bin/code

            runHook postInstall
    '';

    meta = with lib; {
      description = "Visual Studio Code - Microsoft's official build";
      homepage = "https://code.visualstudio.com/";
      license = licenses.unfree;
      platforms = [
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      mainProgram = "code";
    };
  };

in
if stdenv.isDarwin then darwinPackage else linuxPackage
