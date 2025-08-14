local _ = require('gettext')
local util = require('util')

---@class YouTubeVideoInfo
---@field title string The video title
---@field thumbnail_url string The thumbnail image URL

---@class HtmlElement
---@field attributes table<string, string> HTML element attributes

-- **YouTubeUtils** - YouTube video processing utilities
--
-- This utility module handles extraction of YouTube video IDs from various URL formats
-- and generates thumbnail URLs.
---@class YouTubeUtils
---@field extractVideoId fun(url: string|nil): string|nil Extract YouTube video ID from various URL formats
---@field getVideoInfo fun(video_id: string|nil): YouTubeVideoInfo|nil Generate video information with direct thumbnail URL
---@field replaceIframeHtml fun(iframe_html: string): string Replace YouTube iframe HTML with thumbnail
local YouTubeUtils = {}

---Extract YouTube video ID from various URL formats
---@param url string|nil The YouTube URL to process
---@return string|nil video_id The extracted video ID, nil if not found
function YouTubeUtils.extractVideoId(url)
    if not url or type(url) ~= 'string' then
        return nil
    end

    -- Pattern matching for various YouTube URL formats
    local patterns = {
        -- youtube.com/watch?v=ID
        'youtube%.com/watch%?v=([%w%-_]+)',
        -- youtu.be/ID
        'youtu%.be/([%w%-_]+)',
        -- youtube.com/embed/ID
        'youtube%.com/embed/([%w%-_]+)',
        -- youtube-nocookie.com/embed/ID
        'youtube%-nocookie%.com/embed/([%w%-_]+)',
        -- youtube.com/v/ID
        'youtube%.com/v/([%w%-_]+)',
        -- youtube.com/watch?feature=player_embedded&v=ID
        'youtube%.com/watch%?.*v=([%w%-_]+)',
    }

    for _, pattern in ipairs(patterns) do
        local video_id = url:match(pattern)
        if video_id then
            return video_id
        end
    end

    return nil
end

---Generate YouTube video information using direct thumbnail URL
---@param video_id string|nil The YouTube video ID
---@return YouTubeVideoInfo|nil video_info Video information with title and thumbnail_url, nil if invalid video_id
function YouTubeUtils.getVideoInfo(video_id)
    if not video_id or type(video_id) ~= 'string' then
        return nil
    end

    -- Use direct thumbnail URL (fast, no network calls)
    return {
        title = 'YouTube Video Thumbnail',
        thumbnail_url = string.format('https://i.ytimg.com/vi/%s/hqdefault.jpg', video_id),
    }
end

---Replace YouTube iframe HTML with thumbnail figure/img tag
---@param iframe_html string The iframe HTML element
---@return string The replacement figure/img tag or original iframe if not YouTube
function YouTubeUtils.replaceIframeHtml(iframe_html)
    -- Extract src URL from iframe
    local src_url = iframe_html:match('src="([^"]+)"')
    if not src_url then
        return iframe_html -- Keep original if no src found
    end

    -- Extract video ID from the URL
    local video_id = YouTubeUtils.extractVideoId(src_url)
    if not video_id then
        return iframe_html -- Keep original if no video ID found
    end

    -- Get video information
    local video_info = YouTubeUtils.getVideoInfo(video_id)
    if not video_info then
        return iframe_html -- Keep original if fetch fails
    end

    local alt_text = util.htmlEscape(video_info.title)
    local youtube_url = string.format('https://www.youtube.com/watch?v=%s', video_id)

    -- Create clickable thumbnail that opens YouTube video
    return string.format(
        [[
          <a href="%s" target="_blank" rel="noopener noreferrer">
          <figure><img class="youtube-thumbnail" src="%s" alt="%s"></figure>
          </a>
        ]],
        youtube_url,
        video_info.thumbnail_url,
        alt_text
    )
end

return YouTubeUtils
