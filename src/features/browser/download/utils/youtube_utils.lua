local _ = require('gettext')
local socket_url = require('socket.url')
local util = require('util')

---@class YouTubeVideoInfo
---@field title string The video title
---@field thumbnail_url string The thumbnail image URL

---@class HtmlElement
---@field attributes table<string, string> HTML element attributes

-- **YouTubeUtils** - YouTube video processing utilities
--
-- This utility module handles extraction of YouTube video IDs from various URL formats
-- and fetches thumbnail URLs using YouTube's oEmbed API for reliable results.
---@class YouTubeUtils
---@field extractVideoId fun(url: string|nil): string|nil Extract YouTube video ID from various URL formats
---@field fetchVideoInfo fun(video_id: string|nil): YouTubeVideoInfo|nil Fetch video information using oEmbed API
---@field replaceIframeElement fun(iframe_element: HtmlElement|nil): string|nil Replace iframe with thumbnail
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

---Fetch YouTube video information using oEmbed API with fallbacks
---@param video_id string|nil The YouTube video ID
---@return YouTubeVideoInfo|nil video_info Video information with title and thumbnail_url, nil if invalid video_id
function YouTubeUtils.fetchVideoInfo(video_id)
    if not video_id or type(video_id) ~= 'string' then
        return nil
    end

    -- Default fallback values
    local fallback_title = 'YouTube Video Thumbnail'
    local fallback_thumbnail = string.format('https://i.ytimg.com/vi/%s/hqdefault.jpg', video_id)

    -- Try oEmbed API for better quality data
    local video_url = string.format('https://www.youtube.com/watch?v=%s', video_id)
    local oembed_url = string.format(
        'https://www.youtube.com/oembed?url=%s&format=json',
        socket_url.escape(video_url)
    )

    local http = require('socket.http')
    local response_body, status_code = http.request(oembed_url)

    if status_code == 200 and response_body then
        local json = require('json')
        local success, video_data = pcall(json.decode, response_body)

        if success and video_data then
            return {
                title = video_data.title or fallback_title,
                thumbnail_url = video_data.thumbnail_url or fallback_thumbnail,
            }
        end
    end

    -- Return fallbacks if oEmbed fails
    return {
        title = fallback_title,
        thumbnail_url = fallback_thumbnail,
    }
end

---Replace YouTube iframe element with thumbnail (DOM-based)
---@param iframe_element HtmlElement|nil The iframe DOM element from htmlparser
---@return string|nil replacement_html The figure/img tag replacement, nil if not processed
function YouTubeUtils.replaceIframeElement(iframe_element)
    if not iframe_element or not iframe_element.attributes then
        return nil
    end

    local src_url = iframe_element.attributes.src
    if not src_url then
        return nil
    end

    local video_id = YouTubeUtils.extractVideoId(src_url)
    if not video_id then
        return nil
    end

    local video_info = YouTubeUtils.fetchVideoInfo(video_id)
    if not video_info then
        return nil
    end

    local alt_text = util.htmlEscape(video_info.title)

    return string.format(
        '<figure><img class="youtube-thumbnail" src="%s" alt="%s"></figure>',
        video_info.thumbnail_url,
        alt_text
    )
end

return YouTubeUtils
