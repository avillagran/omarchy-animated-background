-- Spaceballs / State Of The Art: Lua port of the spotlight effect in
-- nfd/sota/native/scene.c. The original bitplanes are represented as thick,
-- hard-edged ring layers; no original graphics or animation data is bundled.
return function(t, a)
  local c = {}
  local function add(x) c[#c + 1] = x end
  local function circle(x,y,r,col) add(a.circle(x,y,r,col,false)) end
  local function rect(x,y,w,h,col) add(a.rect(x,y,w,h,col,true)) end
  local W,H = 320,180
  local sx, sy = W / 256, H / 256
  local ms = t * 1000
  local bass, treble = a.bass or 0, a.treble or 0
  local beat = a.beat == true

  add(a.clear("#000000"))

  -- Exact paths from scene_spotlights_tick(). The source scene uses a
  -- nominal 256x256 plane which scrolls across a 256x256 viewport.
  local x1 = (128 + 128 * math.sin(ms / 800)) * sx
  local y1 = (128 + 128 * math.sin(ms / 2000)) * sy
  local x2 = 30 * sx
  local y2 = (128 + 128 * math.sin(1 + ms / 1200)) * sy

  -- draw_thick_circle() uses a 4..6 pixel band. Canvas has no bitplane
  -- primitive, so adjacent one-pixel outlines reproduce that band exactly.
  local thickness = 4 + math.floor(bass * 2)
  local gap = math.max(2, math.floor((2 * thickness) / 3))
  local maxRadius = math.sqrt(W * W + H * H)
  local rings = math.floor(maxRadius / (thickness + gap))
  for i=rings,1,-1 do
    local r = i * (thickness + gap)
    local col = i % 4 == 0 and "#00d4ff" or i % 4 == 1 and "#1977ff" or i % 4 == 2 and "#a800ff" or "#ff20bd"
    for k=0,thickness-1 do circle(x1,y1,r+k,col) end
  end
  for i=rings,1,-1 do
    local r = i * (thickness + gap) + 2
    local col = i % 3 == 0 and "#aaff00" or i % 3 == 1 and "#ffffff" or "#ffcc00"
    for k=0,thickness-1 do circle(x2,y2,r+k,col) end
  end

  -- Copper palette modulation: scene_copperpastels_tick() changes the
  -- palette by scanline. Keep it subtle and behind the bitplane rings.
  for y=0,H-1,4 do
    local p = math.sin(ms / 1600 + y / 24) * 0.5 + 0.5
    local r = math.floor(5 + p * 18 + treble * 10)
    local g = math.floor(3 + p * 8)
    local b = math.floor(12 + p * 28)
    rect(0,y,W,1,string.format("#%02x%02x%02x",r,g,b))
  end

  -- The original has a 50ms display cadence and palette flashes on events.
  -- Audio beat is only an optional palette flash; choreography stays faithful
  -- to the source sine paths.
  if beat then rect(0,0,W,H,"rgba(255,255,255,0.08)") end
  for y=0,H-1,2 do rect(0,y,W,1,"rgba(0,0,0,0.18)") end
  return c
end
