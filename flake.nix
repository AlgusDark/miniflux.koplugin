{
  description = "Miniflux KOReader Plugin Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Simple Lua environment with essential packages only
        luaEnv = pkgs.lua5_1.withPackages (ps: with ps; [
          busted
          # htmlparser installed via luarocks locally when needed
        ]);
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Lua development essentials
            luaEnv                      # lua5_1 + busted
            lua51Packages.luarocks      # Use Lua 5.1 specific luarocks
            lua-language-server         # LSP for IDE diagnostics
            stylua                      # Lua code formatter
            selene                      # Modern Lua linter (Rust-based)
            
            # Build tools (use system git, rsync, zip)
            go-task
          ];

          shellHook = ''
            echo "🎯 Miniflux KOReader Plugin Development Environment"
            echo "📦 Lua 5.1 + busted + luarocks + lua-language-server + stylua + selene"
            echo "✨ Complete development toolchain ready!"
            
            # Ensure htmlparser is available
            luarocks install --local htmlparser 2>/dev/null || true
            
            # Set up luarocks path and project paths
            eval $(luarocks path)
            export LUA_PATH="src/?.lua;src/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"
            
            echo "✅ Environment ready (htmlparser available)"
            echo "🔍 Available commands: task check, task fmt-fix, task build"
          '';

          # Environment variables for development
          STYLUA_CONFIG_PATH = "./stylua.toml";
        };
      });
}