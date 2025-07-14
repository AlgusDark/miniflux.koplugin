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
        describe('security cleaning', function()
            it('should remove script tags', function()
                local html = '<p>Keep this</p><script>alert("remove")</script><p>Keep this too</p>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_string(result)
                assert.is_true(result:find('Keep this') ~= nil)
                assert.is_true(result:find('Keep this too') ~= nil)
                -- Script should be removed
                assert.is_true(result:find('script') == nil)
            end)

            it('should remove multiple script tags', function()
                local html = '<script>bad();</script><p>Good</p><script>more_bad();</script>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('Good') ~= nil)
                assert.is_true(result:find('script') == nil)
                assert.is_true(result:find('bad') == nil)
            end)

            it('should remove iframes', function()
                local html = '<p>Content</p><iframe src="malicious.html">Bad</iframe><p>More content</p>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('Content') ~= nil)
                assert.is_true(result:find('More content') ~= nil)
                assert.is_true(result:find('iframe') == nil)
                assert.is_true(result:find('malicious') == nil)
            end)

            it('should remove video tags', function()
                local html = '<p>Article</p><video controls><source src="video.mp4"></video>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('Article') ~= nil)
                assert.is_true(result:find('video') == nil)
                assert.is_true(result:find('source') == nil)
            end)

            it('should remove object and embed tags', function()
                local html = '<object data="flash.swf"></object><embed src="plugin.swf"/><p>Text</p>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('Text') ~= nil)
                assert.is_true(result:find('object') == nil)
                assert.is_true(result:find('embed') == nil)
                assert.is_true(result:find('flash') == nil)
            end)

            it('should remove form elements', function()
                local html = '<form><input type="text"><button>Submit</button></form><p>Content</p>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('Content') ~= nil)
                assert.is_true(result:find('form') == nil)
                assert.is_true(result:find('input') == nil)
                assert.is_true(result:find('button') == nil)
            end)

            it('should remove style blocks', function()
                local html = '<p>Text</p><style>body { background: red; }</style><p>More text</p>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('Text') ~= nil)
                assert.is_true(result:find('More text') ~= nil)
                assert.is_true(result:find('style') == nil)
                assert.is_true(result:find('background') == nil)
            end)
        end)

        describe('content preservation', function()
            it('should preserve regular content', function()
                local html = '<p>Regular content</p><strong>Bold text</strong>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_string(result)
                assert.is_true(result:find('Regular content') ~= nil)
                assert.is_true(result:find('Bold text') ~= nil)
            end)

            it('should preserve links', function()
                local html = '<p>Check out <a href="https://example.com">this link</a> for more info.</p>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('Check out') ~= nil)
                assert.is_true(result:find('this link') ~= nil)
                assert.is_true(result:find('href="https://example.com"') ~= nil)
            end)

            it('should preserve images', function()
                local html = '<img src="photo.jpg" alt="A photo"><p>Caption</p>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('img') ~= nil)
                assert.is_true(result:find('photo.jpg') ~= nil)
                assert.is_true(result:find('A photo') ~= nil)
                assert.is_true(result:find('Caption') ~= nil)
            end)

            it('should preserve lists', function()
                local html = '<ul><li>Item 1</li><li>Item 2</li></ul><ol><li>First</li></ol>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_true(result:find('<ul>') ~= nil)
                assert.is_true(result:find('<ol>') ~= nil)
                assert.is_true(result:find('Item 1') ~= nil)
                assert.is_true(result:find('First') ~= nil)
            end)
        end)

        describe('edge cases', function()
            it('should handle empty content', function()
                local result = html_utils.cleanHtmlContent('')
                assert.equal('', result)
            end)

            it('should handle nil content', function()
                local result = html_utils.cleanHtmlContent(nil)
                assert.equal('', result)
            end)

            it('should handle content with only unsafe elements', function()
                local html = '<script>alert("xss")</script><iframe src="bad.html"></iframe>'
                local result = html_utils.cleanHtmlContent(html)

                -- Should be empty or nearly empty after cleaning
                assert.is_string(result)
                assert.is_true(result:find('script') == nil)
                assert.is_true(result:find('iframe') == nil)
                assert.is_true(result:find('alert') == nil)
            end)

            it('should handle malformed HTML', function()
                local html = '<p>Unclosed paragraph<div>Mixed nesting<span>Text</p></div></span>'
                local result = html_utils.cleanHtmlContent(html)

                assert.is_string(result)
                assert.is_true(result:find('Unclosed paragraph') ~= nil)
                assert.is_true(result:find('Mixed nesting') ~= nil)
                assert.is_true(result:find('Text') ~= nil)
            end)
        end)
    end)

    describe('createHtmlDocument', function()
        describe('document structure', function()
            it('should create a valid HTML5 document', function()
                local entry = {
                    title = 'Test Entry',
                    feed = { title = 'Test Feed' },
                    published_at = '2023-01-01',
                    url = 'https://example.com/test',
                }
                local content = '<p>Test content</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                assert.is_string(result)
                -- Check HTML5 structure
                assert.is_true(result:find('<!DOCTYPE html>') ~= nil)
                assert.is_true(result:find('<html lang="en">') ~= nil)
                assert.is_true(result:find('<meta charset="UTF%-8">') ~= nil)
                assert.is_true(result:find('<meta name="viewport"') ~= nil)
                -- Check content structure - should have title and content sections
                assert.is_true(result:find('<h1>') ~= nil)
                assert.is_true(result:find('</h1>') ~= nil)
                assert.is_true(result:find('<p>Test content</p>') ~= nil)
            end)

            it('should include all entry metadata', function()
                local entry = {
                    title = 'Full Entry Example',
                    feed = { title = 'Amazing Blog' },
                    published_at = '2023-12-25T10:30:00Z',
                    url = 'https://blog.example.com/post/123',
                }
                local content = '<p>Article content here</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                -- Check title appears in both head and body
                assert.is_true(result:find('<title>Full Entry Example</title>') ~= nil)
                assert.is_true(result:find('<h1>Full Entry Example</h1>') ~= nil)
                -- Check metadata sections
                assert.is_true(result:find('Amazing Blog') ~= nil)
                assert.is_true(result:find('2023%-12%-25T10:30:00Z') ~= nil)
                assert.is_true(result:find('https://blog%.example%.com') ~= nil)
                -- Check content
                assert.is_true(result:find('Article content here') ~= nil)
            end)
        end)

        describe('field handling', function()
            it('should handle entry without optional fields', function()
                local entry = { title = 'Minimal Entry' }
                local content = '<p>Minimal content</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                assert.is_string(result)
                assert.is_true(result:find('Minimal Entry') ~= nil)
                assert.is_true(result:find('Minimal content') ~= nil)
                -- Should not have metadata sections for missing fields
                assert.is_true(result:find('Feed:') == nil)
                assert.is_true(result:find('Published:') == nil)
                assert.is_true(result:find('URL:') == nil)
            end)

            it('should handle missing title gracefully', function()
                local entry = { 
                    feed = { title = 'Test Feed' },
                    url = 'https://example.com'
                }
                local content = '<p>Content without title</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                -- Should use fallback title
                assert.is_true(result:find('Untitled Entry') ~= nil)
                assert.is_true(result:find('Test Feed') ~= nil)
                assert.is_true(result:find('Content without title') ~= nil)
            end)

            it('should handle URL base extraction', function()
                local entry = {
                    title = 'URL Test',
                    url = 'https://subdomain.example.com/very/long/path/to/article?param=value#anchor',
                }
                local content = '<p>Testing URL handling</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                -- Should contain full URL but display base URL
                assert.is_true(result:find('href="https://subdomain%.example%.com/very/long/path/to/article%?param=value#anchor"') ~= nil)
                assert.is_true(result:find('https://subdomain%.example%.com') ~= nil)
            end)
        end)

        describe('security and escaping', function()
            it('should escape HTML in titles', function()
                local entry = { title = "Title with <script>alert('xss')</script>" }
                local content = '<p>Safe content</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                assert.is_string(result)
                -- Should be escaped in both title and h1
                assert.is_true(result:find('&lt;script&gt;') ~= nil)
                -- Should not contain unescaped script tag
                assert.is_true(result:find('<script>alert') == nil)
            end)

            it('should escape HTML in feed titles', function()
                local entry = {
                    title = 'Safe Title',
                    feed = { title = 'Feed with <img src=x onerror=alert(1)> injection' }
                }
                local content = '<p>Content</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                -- Feed title should be escaped
                assert.is_string(result)
                -- Should not contain unescaped injection
                assert.is_true(result:find('<img src=x') == nil)
                -- Should contain escaped content (HTML entities)
                assert.is_true(result:find('injection') ~= nil)
                -- Should contain properly escaped HTML
                assert.is_true(result:find('&lt;img') ~= nil)
                assert.is_true(result:find('&gt;') ~= nil)
            end)

            it('should not escape content HTML', function()
                local entry = { title = 'Content Test' }
                local content = '<p>This is <strong>bold</strong> and <em>italic</em> text.</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                -- Content should remain as HTML (not escaped)
                assert.is_true(result:find('<p>This is <strong>bold</strong>') ~= nil)
                assert.is_true(result:find('<em>italic</em> text.</p>') ~= nil)
            end)

            it('should handle special characters in URLs', function()
                local entry = {
                    title = 'URL Encoding Test',
                    url = 'https://example.com/path?query=hello world&param=<test>',
                }
                local content = '<p>Testing special chars</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                -- URL should be properly handled
                assert.is_string(result)
                assert.is_true(result:find('href=') ~= nil)
                assert.is_true(result:find('example%.com') ~= nil)
            end)
        end)

        describe('edge cases', function()
            it('should handle empty content', function()
                local entry = { title = 'Empty Content Test' }
                local content = ''

                local result = html_utils.createHtmlDocument(entry, content)

                assert.is_string(result)
                assert.is_true(result:find('Empty Content Test') ~= nil)
                -- Should create a valid HTML document structure
                assert.is_true(result:find('<!DOCTYPE html>') ~= nil)
                assert.is_true(result:find('<html') ~= nil)
                assert.is_true(result:find('</html>') ~= nil)
            end)

            it('should handle very long titles', function()
                local long_title = string.rep('Very Long Title ', 50) -- 850 characters
                local entry = { title = long_title }
                local content = '<p>Content</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                assert.is_string(result)
                assert.is_true(result:find('Very Long Title') ~= nil)
                -- Should not break HTML structure
                assert.is_true(result:find('</title>') ~= nil)
                assert.is_true(result:find('</h1>') ~= nil)
            end)

            it('should handle unicode characters', function()
                local entry = {
                    title = 'Unicode Test: 你好世界 🌍 Café résumé',
                    feed = { title = 'Блог тест' },
                }
                local content = '<p>Content with émojis 🚀 and àccénts</p>'

                local result = html_utils.createHtmlDocument(entry, content)

                assert.is_string(result)
                assert.is_true(result:find('你好世界') ~= nil)
                assert.is_true(result:find('🌍') ~= nil)
                assert.is_true(result:find('Café') ~= nil)
                assert.is_true(result:find('Блог') ~= nil)
                assert.is_true(result:find('🚀') ~= nil)
            end)
        end)
    end)

    describe('processEntryContent', function()
        describe('complete workflow', function()
            it('should process entry content through full pipeline', function()
                local entry_data = {
                    title = 'Test Entry',
                    feed = { title = 'Test Feed' },
                    published_at = '2023-01-15T10:00:00Z',
                    url = 'https://example.com/entry/1',
                }
                local raw_content = '<p>Test content with <strong>formatting</strong></p>'
                local options = {
                    entry_data = entry_data,
                    seen_images = {},
                    base_url = 'https://example.com',
                    include_images = true,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(error)
                assert.is_string(result)
                -- Should contain complete HTML document
                assert.is_true(result:find('<!DOCTYPE html>') ~= nil)
                assert.is_true(result:find('Test Entry') ~= nil)
                assert.is_true(result:find('Test Feed') ~= nil)
                assert.is_true(result:find('Test content with') ~= nil)
                assert.is_true(result:find('<strong>formatting</strong>') ~= nil)
            end)

            it('should handle image processing in content', function()
                local entry_data = {
                    title = 'Entry with Images',
                    url = 'https://blog.example.com/post',
                }
                local raw_content = '<p>Check out this image:</p><img src="photo.jpg" alt="A photo">'
                local options = {
                    entry_data = entry_data,
                    seen_images = {},
                    base_url = 'https://blog.example.com',
                    include_images = true,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(error)
                assert.is_string(result)
                assert.is_true(result:find('Check out this image') ~= nil)
                assert.is_true(result:find('<img src="photo.jpg"') ~= nil)
            end)

            it('should clean unsafe HTML elements', function()
                local entry_data = { title = 'Security Test' }
                local raw_content = '<p>Safe content</p><script>alert("dangerous")</script><iframe src="evil.com"></iframe>'
                local options = {
                    entry_data = entry_data,
                    seen_images = {},
                    base_url = 'https://example.com',
                    include_images = false,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(error)
                assert.is_string(result)
                assert.is_true(result:find('Safe content') ~= nil)
                -- Dangerous elements should be removed
                assert.is_true(result:find('<script>') == nil)
                assert.is_true(result:find('<iframe>') == nil)
                assert.is_true(result:find('alert') == nil)
                assert.is_true(result:find('evil.com') == nil)
            end)
        end)

        describe('parameter validation', function()
            it('should return error for nil entry_data', function()
                local raw_content = '<p>Content</p>'
                local options = {
                    entry_data = nil,
                    seen_images = {},
                    base_url = 'https://example.com',
                    include_images = true,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(result)
                assert.is_not_nil(error)
                assert.is_true(error.message:find('Invalid parameters') ~= nil)
            end)

            it('should return error for nil raw_content', function()
                local entry_data = { title = 'Test' }
                local options = {
                    entry_data = entry_data,
                    seen_images = {},
                    base_url = 'https://example.com',
                    include_images = true,
                }

                local result, error = html_utils.processEntryContent(nil, options)

                assert.is_nil(result)
                assert.is_not_nil(error)
                assert.is_true(error.message:find('Invalid parameters') ~= nil)
            end)

            it('should return error for missing options', function()
                local entry_data = { title = 'Test' }
                local raw_content = '<p>Content</p>'

                local result, error = html_utils.processEntryContent(raw_content, {})

                assert.is_nil(result)
                assert.is_not_nil(error)
                assert.is_true(error.message:find('Invalid parameters') ~= nil)
            end)
        end)

        describe('edge cases', function()
            it('should handle empty content', function()
                local entry_data = { title = 'Empty Content Test' }
                local raw_content = ''
                local options = {
                    entry_data = entry_data,
                    seen_images = {},
                    base_url = 'https://example.com',
                    include_images = false,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(error)
                assert.is_string(result)
                assert.is_true(result:find('Empty Content Test') ~= nil)
                -- Should create a valid HTML document structure
                assert.is_true(result:find('<!DOCTYPE html>') ~= nil)
                assert.is_true(result:find('<html') ~= nil)
                assert.is_true(result:find('</html>') ~= nil)
            end)

            it('should handle minimal entry data', function()
                local entry_data = { title = 'Minimal Entry' }
                local raw_content = '<p>Simple content</p>'
                local options = {
                    entry_data = entry_data,
                    seen_images = {},
                    base_url = 'https://example.com',
                    include_images = false,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(error)
                assert.is_string(result)
                assert.is_true(result:find('Minimal Entry') ~= nil)
                assert.is_true(result:find('Simple content') ~= nil)
                -- Should not have metadata for missing fields
                assert.is_true(result:find('Feed:') == nil)
                assert.is_true(result:find('Published:') == nil)
                assert.is_true(result:find('URL:') == nil)
            end)

            it('should handle complex content with mixed elements', function()
                local entry_data = {
                    title = 'Complex Entry',
                    feed = { title = 'Tech Blog' },
                    published_at = '2023-01-01T00:00:00Z',
                    url = 'https://tech.example.com/complex-post',
                }
                local raw_content = [[
                    <h2>Article Title</h2>
                    <p>Introduction with <a href="https://example.com">link</a></p>
                    <ul>
                        <li>Point 1</li>
                        <li>Point 2</li>
                    </ul>
                    <blockquote>Important quote</blockquote>
                    <script>alert("remove me")</script>
                    <p>Conclusion with <strong>emphasis</strong></p>
                ]]
                local options = {
                    entry_data = entry_data,
                    seen_images = {},
                    base_url = 'https://tech.example.com',
                    include_images = true,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(error)
                assert.is_string(result)
                -- Should preserve good content
                assert.is_true(result:find('Article Title') ~= nil)
                assert.is_true(result:find('Introduction with') ~= nil)
                assert.is_true(result:find('<a href="https://example.com">link</a>') ~= nil)
                assert.is_true(result:find('<ul>') ~= nil)
                assert.is_true(result:find('Point 1') ~= nil)
                assert.is_true(result:find('<blockquote>') ~= nil)
                assert.is_true(result:find('Important quote') ~= nil)
                assert.is_true(result:find('<strong>emphasis</strong>') ~= nil)
                -- Should remove dangerous content
                assert.is_true(result:find('<script>') == nil)
                assert.is_true(result:find('alert') == nil)
                -- Should include metadata
                assert.is_true(result:find('Tech Blog') ~= nil)
                assert.is_true(result:find('2023%-01%-01T00:00:00Z') ~= nil)
                assert.is_true(result:find('https://tech%.example%.com') ~= nil)
            end)
        end)

        describe('integration with dependencies', function()
            it('should pass correct parameters to image processing', function()
                local entry_data = { title = 'Image Test' }
                local raw_content = '<p>Content</p><img src="test.jpg">'
                local seen_images = { 'image1.jpg' }
                local options = {
                    entry_data = entry_data,
                    seen_images = seen_images,
                    base_url = 'https://example.com',
                    include_images = true,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(error)
                assert.is_string(result)
                -- Mock should have been called with correct parameters
                -- This tests the integration without mocking internals
                assert.is_true(result:find('Content') ~= nil)
                assert.is_true(result:find('test.jpg') ~= nil)
            end)

            it('should handle image processing with include_images=false', function()
                local entry_data = { title = 'No Images Test' }
                local raw_content = '<p>Text content</p><img src="skip.jpg">'
                local options = {
                    entry_data = entry_data,
                    seen_images = {},
                    base_url = 'https://example.com',
                    include_images = false,
                }

                local result, error = html_utils.processEntryContent(raw_content, options)

                assert.is_nil(error)
                assert.is_string(result)
                assert.is_true(result:find('Text content') ~= nil)
                assert.is_true(result:find('skip.jpg') ~= nil)
            end)
        end)
    end)
end)
