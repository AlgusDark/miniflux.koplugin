{
  description = "Miniflux KOReader Plugin Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Lua development (following real-world examples)
            lua5_1
            luarocks                    # Direct inclusion like lua-enum
            lua51Packages.luacheck      # From nixpkgs
            lua51Packages.busted        # From nixpkgs
            
            # Code quality
            stylua
            lua-language-server
            
            # Build tools
            go-task
            git
            rsync
            zip
          ];

          shellHook = ''
            echo "🎯 Miniflux KOReader Plugin Development Environment"
            echo "📦 Lua 5.1 + LuaRocks available"
            echo "💡 Install additional packages: luarocks install --local <package>"
            echo "🔍 Available commands: task check, task fmt-fix, task build"
            
            # Set up project Lua paths
            export LUA_PATH="src/?.lua;src/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"
            
            # Ensure git hooks are executable
            if [ -d .githooks ]; then
              chmod +x .githooks/*
            fi
            
            # Suggest git hooks setup if not configured
            if [ "$(git config core.hooksPath)" != ".githooks" ]; then
              echo "💡 Tip: Run '.githooks/setup.sh' to enable pre-commit hooks"
            fi
          '';

          # Environment variables for development
          STYLUA_CONFIG_PATH = "./stylua.toml";
          LUACHECK_CONFIG = "./.luacheckrc";
        };
      });
}