{
  description = "Miniflux KOReader Plugin Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
    luarocks-nix = {
      url = "github:nix-community/luarocks-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, flake-utils, luarocks-nix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Create htmlparser as a proper Nix package using luarocks-nix
        htmlparser = pkgs.lua51Packages.buildLuarocksPackage {
          pname = "htmlparser";
          version = "0.3.9-1";
          
          src = pkgs.fetchurl {
            url = "https://luarocks.org/htmlparser-0.3.9-1.src.rock";
            sha256 = "sha256-iHKqsE6+fZiGyxKqfXsRxtOL9YcqOHHl7KI9Y2bEAZ4=";
          };
          
          # No additional dependencies needed for htmlparser
          propagatedBuildInputs = [ ];
        };
        
        # Enhanced Lua environment with proper Nix packages
        luaEnv = pkgs.lua5_1.withPackages (ps: with ps; [
          luacheck
          busted
          htmlparser  # Now a proper Nix package!
        ]);
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Lua development with integrated packages
            luaEnv                      # Includes lua5_1 + luacheck + busted + htmlparser
            
            # Code quality
            stylua
            lua-language-server
            
            # Build tools (use system git, rsync, zip)
            go-task
          ];

          shellHook = ''
            echo "🎯 Miniflux KOReader Plugin Development Environment"
            echo "📦 Lua 5.1 + luacheck + busted + htmlparser (via Nix)"
            echo "✨ All packages managed by Nix - fully reproducible!"
            echo "🔍 Available commands: task check, task fmt-fix, task build"
            
            # Set up project Lua paths
            export LUA_PATH="src/?.lua;src/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"
            
            # Set up git hooks automatically
            if [ -d .githooks ]; then
              chmod +x .githooks/*
              git config --get core.hooksPath >/dev/null || {
                git config core.hooksPath .githooks
                echo "🪝 Git hooks enabled automatically"
              }
            fi
          '';

          # Environment variables for development
          STYLUA_CONFIG_PATH = "./stylua.toml";
          LUACHECK_CONFIG = "./.luacheckrc";
        };
      });
}