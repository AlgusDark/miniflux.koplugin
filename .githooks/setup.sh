#!/bin/bash
# Setup script for git hooks

echo "🔧 Setting up git hooks for code quality..."

# Configure git to use our custom hooks directory
git config core.hooksPath .githooks

echo "✅ Git hooks configured!"
echo ""
echo "📋 Available hooks:"
echo "  - pre-commit: Runs code formatting and linting checks"
echo ""
echo "💡 To bypass hooks (emergency commits only): git commit --no-verify"
echo ""
echo "🚀 Next steps:"
echo "  1. Install dependencies:"
echo "     - cargo install stylua"
echo "     - luarocks install luacheck"
echo "  2. Test: task check"