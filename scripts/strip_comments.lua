-- Usage: lua strip_comments.lua input.lua output.lua

local infile, outfile = ...

if not infile or not outfile then
  io.stderr:write("Usage: lua strip_comments.lua <in> <out>\n")
  os.exit(1)
end

local fh = io.open(infile, "r")
if not fh then
  io.stderr:write("Cannot open input file: "..infile.."\n")
  os.exit(1)
end
local text = fh:read("*a")
fh:close()

-- remove block comments --[[ … ]]
text = text:gsub("%-%-%[%[.-%]%]", "")

-- remove all remaining line comments (including annotations starting with ---)
text = text:gsub("%-%-.-\n", "\n")

-- ensure trailing newline
if not text:match("\n$") then text = text .. "\n" end

local ofh = io.open(outfile, "w")
if not ofh then
  io.stderr:write("Cannot open output file: "..outfile.."\n")
  os.exit(1)
end
ofh:write(text)
ofh:close()