{
  description = "KOReader Plugin Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            lua5_1 # Lua 5.1
            lua-language-server # LSP for IDE diagnostics
            stylua # Lua code formatter
            selene # Modern Lua linter (Rust-based)

            # Build tools
            go-task
            git-cliff # Changelog generator
          ];

          shellHook = ''
            echo "🎯 KOReader Plugin Development Environment"
            echo "📦 Lua 5.1 + lua-language-server + stylua + selene"
            echo "✨ Complete development toolchain ready!"

            export LUA_PATH="src/?.lua;src/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"

            echo "✅ Environment ready"
            echo "🔍 Available commands: task check, task fmt-fix, task build"
          '';

          # Environment variables for development
          STYLUA_CONFIG_PATH = "./stylua.toml";
        };
      });
}


