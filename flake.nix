{
  description = "Auto-updating VS Code Nix flake with Microsoft's official binaries";

  nixConfig = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        inherit (pkgs) stdenv;
        vscode = pkgs.callPackage ./package.nix { };

        # Helper function to create VS Code with extensions, optional settings, and optional keybindings
        vscodeWithExtensions =
          extensions: settings:
          let
            settingsArgs =
              if settings == null then
                {
                  settings = null;
                  keybindings = null;
                }
              else if builtins.isAttrs settings && (settings ? settings || settings ? keybindings) then
                {
                  settings = settings.settings or null;
                  keybindings = settings.keybindings or null;
                }
              else
                {
                  settings = settings;
                  keybindings = null;
                };
          in
          pkgs.callPackage ./package.nix {
            inherit extensions;
            userSettings = settingsArgs.settings;
            userKeybindings = settingsArgs.keybindings;
          };
      in
      {
        packages = {
          inherit vscode;
          default = vscode;
        };

        apps = {
          vscode = {
            type = "app";
            program = "${vscode}/bin/code";
            meta.description = "Visual Studio Code - Microsoft's official build";
          };
          default = self.apps.${system}.vscode;
        };

        # Export lib with vscodeWithExtensions function
        lib = {
          inherit vscodeWithExtensions;
        };

        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixpkgs-fmt
            nix-prefetch
            gh
            jq
          ];
        };

        # Checks for `nix flake check`
        checks =
          let
            # Helper to find the wrapper script path
            # On Linux, wrapGAppsHook3 wraps to .code-wrapped; on macOS it's just code
            findWrapper = pkg: if stdenv.isDarwin then "${pkg}/bin/code" else "${pkg}/bin/.code-wrapped";
          in
          {
            # Basic build check - ensures the default package builds
            build = vscode;

            # Wrapper syntax check - validates bash syntax of the wrapper script
            wrapper-syntax = pkgs.runCommand "vscode-wrapper-syntax-check" { } ''
              ${pkgs.bash}/bin/bash -n ${findWrapper vscode}
              echo "Wrapper script syntax OK" > $out
            '';

            # Build with sample extensions list
            with-extensions =
              let
                vscodeWithExt = vscodeWithExtensions [ "jnoortheen.nix-ide" ] null;
              in
              pkgs.runCommand "vscode-with-extensions-check" { } ''
                # Verify the package built successfully
                test -x ${vscodeWithExt}/bin/code
                # Verify wrapper syntax
                ${pkgs.bash}/bin/bash -n ${findWrapper vscodeWithExt}
                echo "Build with extensions OK" > $out
              '';

            # Build with sample settings
            with-settings =
              let
                vscodeWithSettings = vscodeWithExtensions [ ] { "editor.fontSize" = 14; };
              in
              pkgs.runCommand "vscode-with-settings-check" { } ''
                # Verify the package built successfully
                test -x ${vscodeWithSettings}/bin/code
                # Verify wrapper syntax
                ${pkgs.bash}/bin/bash -n ${findWrapper vscodeWithSettings}
                echo "Build with settings OK" > $out
              '';
          };
      }
    )
    // {
      overlays.default = final: prev: {
        vscode-nix = self.packages.${prev.system}.vscode;
      };
    };
}
