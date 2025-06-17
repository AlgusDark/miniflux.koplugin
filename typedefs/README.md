# KOReader Type Definitions

This directory contains EmmyLua type definitions for **external KOReader classes** used in the Miniflux plugin. These are types we don't control and that don't have built-in type definitions.

## Important: Co-located Types

**Our own types** (like `MinifluxEntry`, `NavigationContext`, etc.) should be **co-located with their implementations**, not in this directory. This follows modern best practices:

- **External types** (KOReader classes) → `typedefs/` directory
- **Internal types** (our plugin types) → Co-located with implementation

## Organization

Each typedef file contains:
- Complete class definition with `@class` annotation
- All relevant fields with `@field` annotations  
- Method signatures with proper parameter and return types
- Comprehensive documentation

## Usage

These files provide IDE support and type checking for development. The type definitions help with:

- **Autocomplete**: Better code completion in IDEs
- **Error Detection**: Catch type-related errors during development
- **Documentation**: Self-documenting code with clear interfaces
- **Maintainability**: Easier code navigation and refactoring

## Files

### KOReader UI Components
- `LuaSettings.lua` - Settings persistence and management
- `WidgetContainer.lua` - Base widget container class
- `Menu.lua` - Menu widget with navigation
- `UIManager.lua` - UI management and widget display
- `InfoMessage.lua` - Information message dialogs
- `MultiInputDialog.lua` - Multi-field input dialogs
- `ButtonDialogTitle.lua` - Button dialogs with titles

### KOReader System Components
- `DataStorage.lua` - Data and settings storage paths

## Adding New External Types

To add new KOReader type definitions:

1. Create a new `.lua` file named after the class
2. Add proper module documentation
3. Define the class with `@class ClassName`
4. Add all fields with `@field` annotations
5. Include method signatures with parameter and return types

## Example

```lua
--[[--
EmmyLua type definitions for MyWidget

@module koplugin.miniflux.typedefs.MyWidget
--]]--

---@class MyWidget
---@field property string Widget property
---@field method fun(self: MyWidget, param: string): boolean Widget method
```

## Do NOT Add Here

- **Plugin-specific types** → Co-locate with implementation
- **API response types** → Define in API modules
- **Browser types** → Define in browser modules
- **Settings types** → Define in settings modules

## Cleanup Notes

Only essential KOReader interface types are kept here. Unused typedefs like `TextViewer` have been removed to reduce maintenance overhead. All remaining typedefs are actively used in the codebase and provide valuable IDE support for KOReader integration.

This approach makes type definitions much easier to maintain and follows modern software engineering principles. 