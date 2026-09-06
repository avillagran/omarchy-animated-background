#!/usr/bin/env lua
-- Programmable RETRO frame server.
-- Supports the native return-function API and PlebsPlayer's global render() API.
-- stdin:  frame <n> [bass <0..1>] [mid <0..1>] [treble <0..1>] [beat <0|1>]
-- stdout: one JSON command frame per request

local scene_path = arg[1]
if not scene_path then os.exit(2) end
local chunk, err = loadfile(scene_path)
if not chunk then io.stderr:write(err .. "\n"); os.exit(1) end
local returned = chunk()
local native_render = type(returned) == "function" and returned or (type(returned) == "table" and returned.render)
local plebs_render = type(_G.render) == "function" and _G.render or nil
if type(native_render) ~= "function" and not plebs_render then
  io.stderr:write("scene must return a function or define render()\n"); os.exit(1)
end

local commands = {}
local function command(name, ...) return {name, ...} end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function byte(v) return math.floor(clamp(tonumber(v) or 0, 0, 255) + 0.5) end
local function rgb(r,g,b) return string.format("#%02x%02x%02x", byte(r), byte(g), byte(b)) end
local function rgba(r,g,b,a) return string.format("rgba(%d,%d,%d,%.4f)", byte(r),byte(g),byte(b),clamp((tonumber(a) or 255)/255,0,1)) end
local function hsv(h,s,v,a)
  h = (tonumber(h) or 0) % 360; s=clamp(tonumber(s) or 0,0,1); v=clamp(tonumber(v) or 0,0,1)
  local c=v*s; local x=c*(1-math.abs((h/60)%2-1)); local m=v-c
  local r,g,b
  if h<60 then r,g,b=c,x,0 elseif h<120 then r,g,b=x,c,0 elseif h<180 then r,g,b=0,c,x elseif h<240 then r,g,b=0,x,c elseif h<300 then r,g,b=x,0,c else r,g,b=c,0,x end
  r,g,b=(r+m)*255,(g+m)*255,(b+m)*255
  return a == nil and rgb(r,g,b) or rgba(r,g,b,a)
end
local function add(name, ...) commands[#commands+1] = command(name, ...) end
local api = {
  W=320, H=180,
  bass=0, mid=0, treble=0, beat=false,
  spectrum={}, waveform={},
  clear=function(c) return command("clear",c) end,
  rect=function(x,y,w,h,c,fill) return command("rect",x,y,w,h,c,fill) end,
  line=function(x1,y1,x2,y2,c,width) return command("line",x1,y1,x2,y2,c,width or 1) end,
  circle=function(x,y,r,c,fill) return command("circle",x,y,r,c,fill) end,
  poly=function(points,c,fill) return command("poly",points,c,fill) end,
}
local function install_plebs_api(frame, bass, mid, treble, beat)
  _G.width, _G.height, _G.time, _G.delta = 320, 180, frame / 30, 1/30
  _G.bass, _G.mid, _G.treble, _G.beat = bass, mid, treble, beat
  _G.spectrum = api.spectrum; _G.waveform = api.waveform
  _G.clamp, _G.lerp = clamp, function(a,b,x) return a+(b-a)*x end
  _G.rgb, _G.rgba, _G.hsv, _G.hsva = rgb, rgba, hsv, function(h,s,v,a) return hsv(h,s,v,a) end
  _G.clear = function(c) add("clear",c) end
  _G.rect = function(x,y,w,h,c,fill) add("rect",x,y,w,h,c,fill) end
  _G.line = function(x1,y1,x2,y2,c,w) add("line",x1,y1,x2,y2,c,w or 1) end
  _G.circle = function(x,y,r,c,fill) add("circle",x,y,r,c,fill) end
  _G.poly = function(points,c,fill) add("poly",points,c,fill) end
  _G.wave = function(points,c,w)
    for i=2,#points do
      local p,q=points[i-1],points[i]; add("line",p[1],p[2],q[1],q[2],c,w or 1)
    end
  end
  _G.random = math.random
end
local function json(v)
  if type(v)=="string" then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')..'"' end
  if type(v)=="number" then return tostring(v) end
  if type(v)=="boolean" then return v and "true" or "false" end
  if type(v)=="table" then
    local n=0; for k in pairs(v) do if type(k)=="number" then n=math.max(n,k) end end
    local out={}; for i=1,n do out[#out+1]=json(v[i]) end
    return "["..table.concat(out,",").."]"
  end
  return "null"
end
local initialized = false
for input in io.lines() do
  local frame = tonumber(input:match("^frame%s+(%d+)") or "0") or 0
  local bass = tonumber(input:match("bass%s+([%d%.%-]+)")) or 0
  local mid = tonumber(input:match("mid%s+([%d%.%-]+)")) or 0
  local treble = tonumber(input:match("treble%s+([%d%.%-]+)")) or 0
  local beat = input:match("beat%s+1") ~= nil
  local function parse_values(key)
    local raw = input:match(key .. "%s+([%d%.,%-]+)") or ""
    local values = {}
    for value in raw:gmatch("%-?[%d%.]+") do values[#values + 1] = tonumber(value) or 0 end
    return values
  end
  api.spectrum, api.waveform = parse_values("spectrum"), parse_values("waveform")
  commands = {}
  api.bass, api.mid, api.treble, api.beat = bass, mid, treble, beat
  local ok, result
  if native_render then
    ok, result = pcall(native_render, frame, api)
    if ok then commands = result or {} end
  else
    install_plebs_api(frame,bass,mid,treble,beat)
    if not initialized and type(_G.setup)=="function" then pcall(_G.setup); initialized=true end
    ok, result = pcall(plebs_render)
  end
  if not ok then io.stderr:write(tostring(result).."\n"); commands={command("clear","#000000")} end
  io.write(json(commands).."\n"); io.stdout:flush()
end
