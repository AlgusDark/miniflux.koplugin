{
  description = "Miniflux KOReader Plugin Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Create a custom Lua environment with luarocks
        luaEnv = pkgs.lua51.withPackages (ps: with ps; [
          luacheck      # Static analysis and linting
          busted        # Testing framework  
          htmlparser    # HTML parsing (dev dependency for tests)
        ]);

        # Development shell script for setup
        devShellScript = pkgs.writeShellScriptBin "miniflux-setup" ''
          echo "🚀 Miniflux KOReader Plugin Development Environment"
          echo ""
          echo "📦 Available tools:"
          echo "  - lua (5.1): $(lua -v)"
          echo "  - luacheck: $(luacheck --version)"
          echo "  - stylua: $(stylua --version)"
          echo "  - busted: $(busted --version 2>/dev/null || echo 'Available')"
          echo "  - task: $(task --version)"
          echo "  - git: $(git --version)"
          echo ""
          echo "🔧 Setup commands:"
          echo "  task check     - Run code quality checks"
          echo "  task fmt-fix   - Auto-fix code formatting"
          echo "  task build     - Build plugin distribution"
          echo ""
          echo "🪝 Git hooks:"
          echo "  .githooks/setup.sh  - Enable pre-commit hooks"
          echo ""
        '';

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core Lua development
            luaEnv                # Lua 5.1 + luarocks packages
            lua-language-server   # LuaLS for type checking and LSP
            
            # Code quality tools
            stylua               # Lua formatter
            
            # Build and task management
            go-task              # Task runner (Taskfile.yml)
            
            # Version control and utilities
            git                  # Git (for hooks and development)
            rsync                # File sync (used in Taskfile.yml)
            zip                  # Archive creation (used in Taskfile.yml)
            
            # Development utilities
            devShellScript       # Custom setup script
            
            # Optional: KOReader development (if you want to test locally)
            # Uncomment these if you plan to run KOReader locally for testing
            # cmake
            # pkg-config
            # SDL2
            # gcc
          ];

          shellHook = ''
            # Welcome message
            echo "🎯 Entering Miniflux KOReader Plugin development environment"
            
            # Set up Lua environment
            export LUA_PATH="src/?.lua;src/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"
            export LUA_CPATH="./?.so;./?/init.so;$LUA_CPATH"
            
            # Ensure git hooks are executable (in case they're not)
            if [ -d .githooks ]; then
              chmod +x .githooks/*
            fi
            
            # Run the setup script to show available tools
            miniflux-setup
            
            # Check if git hooks are set up
            if [ "$(git config core.hooksPath)" != ".githooks" ]; then
              echo "💡 Tip: Run '.githooks/setup.sh' to enable pre-commit hooks"
              echo ""
            fi
          '';

          # Environment variables for development
          STYLUA_CONFIG_PATH = "./stylua.toml";
          LUACHECK_CONFIG = "./.luacheckrc";
        };

        # Apps for easy access to tools
        apps = {
          # Quick access to common commands
          check = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "check" ''
              exec task check
            '';
          };
          
          format = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "format" ''
              exec task fmt-fix
            '';
          };
          
          build = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "build" ''
              exec task build
            '';
          };
        };

        # Optional: Package the plugin for distribution
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "miniflux-koplugin";
          version = "0.0.1";
          
          src = ./.;
          
          buildInputs = [ pkgs.go-task ];
          
          buildPhase = ''
            task build
          '';
          
          installPhase = ''
            mkdir -p $out
            cp -r dist/miniflux.koplugin $out/
          '';
        };
      }
    );
}