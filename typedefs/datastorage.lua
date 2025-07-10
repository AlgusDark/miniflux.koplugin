---@meta
---@module 'datastorage'

---@class DataStorage
---@field getSettingsDir fun(): string Get settings directory path
---@field getDataDir fun(): string Get data directory path
---@field getFullDataDir fun(): string Get full data directory path
local DataStorage = {}

return DataStorage