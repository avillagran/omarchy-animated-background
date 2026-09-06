-- TRON / outrun sunset: procedural synthwave scene.
-- The renderer uses only circles, rectangles and perspective lines.
return function(t, a)
  local c = {}
  local function add(x) c[#c + 1] = x end
  local function rect(x,y,w,h,col) add(a.rect(x,y,w,h,col)) end
  local function line(x1,y1,x2,y2,col,w) add(a.line(x1,y1,x2,y2,col,w or 1)) end
  local function circle(x,y,r,col) add(a.circle(x,y,r,col)) end

  local W, H = 320, 180
  local horizon = 111
  local vanishX = 160
  local bass = a.bass or 0
  local mid = a.mid or 0
  local treble = a.treble or 0
  local beat = a.beat == true

  add(a.clear("#09091f"))

  -- Layered sky: deep indigo to hot violet at the horizon.
  local sky = {
    "#09091f", "#100b2c", "#170d3b", "#220f4b", "#301052",
    "#45145c", "#60185f", "#801d65", "#a62a6b", "#cf4771", "#e96a78"
  }
  for i, col in ipairs(sky) do
    rect(0, (i-1)*10, W, 11, col)
  end

  -- Sparse stars, kept away from the sun.
  for i=1,34 do
    local x = (i * 83 + 17) % W
    local y = (i * 47 + 9) % 74
    if math.abs(x - vanishX) > 48 then
      rect(x, y, i % 3 == 0 and 2 or 1, 1, i % 4 == 0 and "#ffd9fa" or "#8bc9ef")
    end
  end

  -- Large circular sunset, built from concentric procedural circles.
  local sunX, sunY, sunR = 160, 72, 40 + bass * 6
  local sun = {
    {40,"#ef5b70"}, {36,"#f57870"}, {32,"#fa8a70"},
    {28,"#ff9c70"}, {24,"#ffae70"}, {20,"#ffc073"},
    {16,"#ffd07d"}, {12,"#ffdf8b"}, {8,"#ffe99a"}, {4,"#fff0ad"}
  }
  for _, ring in ipairs(sun) do circle(sunX, sunY, ring[1], ring[2]) end

  -- Classic sliced lower sun. Each slit is clipped to the circular silhouette.
  for y=75,112,5 do
    local dy = y - sunY
    local half = math.sqrt(math.max(0, sunR*sunR - dy*dy))
    if half > 0 then rect(sunX-half, y, half*2, 2, beat and "#76265f" or "#9e3568") end
  end

  -- Horizon bloom, strongest below the sun.
  for i=0,7 do
    local col = (i % 2 == 0) and "#d83b9a" or "#8d277f"
    line(0, horizon + i*2, W, horizon + i*2, col, i < 2 and (2 + math.floor(bass * 2)) or 1)
  end
  line(0, horizon, W, horizon, "#ff9adf", 2)
  line(48, horizon+3, 272, horizon+3, "#ff4fca", 1)

  -- Dark reflective plane below the horizon.
  rect(0, horizon+9, W, H-horizon-9, "#070817")
  rect(0, horizon+9, W, 8, "#120c2d")
  rect(0, horizon+17, W, 8, "#0d0a25")

  -- Perspective floor: horizontal lines travel toward the viewer.
  local phase = (t * (0.030 + bass * 0.045 + mid * 0.012)) % 1
  for i=0,18 do
    local d = ((i + phase) / 19) ^ 2
    local y = horizon + 7 + d * (H - horizon + 20)
    if y < H then
      local col = i % 4 == 0 and (beat and "#ffb4ed" or "#f34ac8") or "#8d35b5"
      line(0, y, W, y, col, i % 4 == 0 and 2 or 1)
    end
  end

  -- One-point perspective rails, perfectly symmetrical around the sun.
  for x=-320,640,20 do
    local col = (x == 0 or x == 320) and "#ef4ecb" or (treble > 0.55 and "#bb55df" or "#a338ba")
    line(vanishX, horizon, x, H, col, x % 40 == 0 and 2 or 1)
  end

  -- Restore a crisp horizon over the grid and add CRT scanlines.
  line(0, horizon, W, horizon, "#ffb2ec", 2)
  if beat then rect(0, 0, W, H, "rgba(255, 100, 220, 0.10)") end
  for y=0,178,2 do rect(0, y, W, 1, "#000000") end

  return c
end
