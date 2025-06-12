# KOReader Type Definitions

This directory contains EmmyLua type definitions for KOReader classes used in the Miniflux plugin. Each file defines types for a specific KOReader class or module.

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

- `LuaSettings.lua` - Settings persistence and management
- `WidgetContainer.lua` - Base widget container class
- `Menu.lua` - Menu widget with navigation
- `UIManager.lua` - UI management and widget display
- `InfoMessage.lua` - Information message dialogs
- `MultiInputDialog.lua` - Multi-field input dialogs
- `ButtonDialogTitle.lua` - Button dialogs with titles
- `DataStorage.lua` - Data and settings storage paths
- `TextViewer.lua` - Text viewing widget

## Adding New Types

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

This modular approach makes type definitions much easier to maintain and extend as the project grows. 