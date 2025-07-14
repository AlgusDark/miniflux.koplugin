describe('html_utils', function()
    local html_utils
    local KOReaderMocks

    setup(function()
        -- Add project paths to require search
        package.path = 'src/?.lua;src/?/init.lua;spec/?.lua;spec/?/init.lua;' .. package.path

        -- Set up KOReader mocks before requiring our modules
        KOReaderMocks = require('helpers/koreader_mocks')
        KOReaderMocks.setup()

        -- Mock additional dependencies that html_utils needs
        package.preload['utils/images'] = function()
            return {
                processHtmlImages = function(content, options)
                    -- Simple passthrough for testing
                    return content
                end,
            }
        end

        html_utils = require('utils/html_utils')
    end)

    teardown(function()
        if KOReaderMocks then
            KOReaderMocks.teardown()
        end
    end)

    describe('cleanHtmlContent', function()
        it('should remove script tags', function()
            local html = '<p>Keep this</p><script>alert("remove")</script><p>Keep this too</p>'
            local result = html_utils.cleanHtmlContent(html)

            assert.is_string(result)
            assert.is_true(result:find('Keep this') ~= nil)
            assert.is_true(result:find('Keep this too') ~= nil)
            -- Script should be removed
            assert.is_true(result:find('script') == nil)
        end)

        it('should handle empty content', function()
            local result = html_utils.cleanHtmlContent('')
            assert.equal('', result)
        end)

        it('should handle nil content', function()
            local result = html_utils.cleanHtmlContent(nil)
            assert.equal('', result)
        end)

        it('should preserve regular content', function()
            local html = '<p>Regular content</p><strong>Bold text</strong>'
            local result = html_utils.cleanHtmlContent(html)

            assert.is_string(result)
            assert.is_true(result:find('Regular content') ~= nil)
            assert.is_true(result:find('Bold text') ~= nil)
        end)
    end)

    describe('createHtmlDocument', function()
        it('should create a valid HTML document', function()
            local entry = {
                title = 'Test Entry',
                feed = { title = 'Test Feed' },
                published_at = '2023-01-01',
                url = 'https://example.com/test',
            }
            local content = '<p>Test content</p>'

            local result = html_utils.createHtmlDocument(entry, content)

            assert.is_string(result)
            assert.is_true(result:find('<!DOCTYPE html>') ~= nil)
            assert.is_true(result:find('Test Entry') ~= nil)
            assert.is_true(result:find('Test content') ~= nil)
            assert.is_true(result:find('Test Feed') ~= nil)
        end)

        it('should handle entry without optional fields', function()
            local entry = { title = 'Minimal Entry' }
            local content = '<p>Minimal content</p>'

            local result = html_utils.createHtmlDocument(entry, content)

            assert.is_string(result)
            assert.is_true(result:find('Minimal Entry') ~= nil)
            assert.is_true(result:find('Minimal content') ~= nil)
        end)

        it('should escape HTML in titles', function()
            local entry = { title = "Title with <script>alert('xss')</script>" }
            local content = '<p>Safe content</p>'

            local result = html_utils.createHtmlDocument(entry, content)

            assert.is_string(result)
            -- Should be escaped
            assert.is_true(result:find('&lt;script&gt;') ~= nil)
            -- Should not contain unescaped script tag
            assert.is_true(result:find('<script>alert') == nil)
        end)
    end)
end)
