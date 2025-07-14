-- koreader mocks for testing
-- this module provides mock implementations of koreader-specific dependencies
-- that are needed for unit testing our code outside of the koreader environment.

local koreadermocks = {}

-- mock gettext translation function
local function mockgettext(text)
    -- simple passthrough for testing - just return the original text
    return text
end

-- mock util module with essential functions
local mockutil = {
    htmlEscape = function(text)
        if not text then
            return ''
        end
        -- basic html escaping for testing
        return text:gsub('&', '&amp;')
            :gsub('<', '&lt;')
            :gsub('>', '&gt;')
            :gsub('"', '&quot;')
            :gsub("'", '&#39;')
    end,
}

-- function to set up all koreader mocks in the global environment
function koreadermocks.setup()
    -- mock gettext as both function and module
    package.preload['gettext'] = function()
        return mockgettext
    end
    _G._ = mockgettext -- global gettext function

    -- mock util module
    package.preload['util'] = function()
        return mockutil
    end

    -- mock other common koreader dependencies that might be needed
    package.preload['logger'] = function()
        return {
            info = function() end,
            warn = function() end,
            err = function() end,
            dbg = function() end,
        }
    end
end

-- function to clean up mocks (useful for test isolation)
function koreadermocks.teardown()
    package.preload['gettext'] = nil
    package.preload['util'] = nil
    package.preload['logger'] = nil
    _G._ = nil
end

return koreadermocks

