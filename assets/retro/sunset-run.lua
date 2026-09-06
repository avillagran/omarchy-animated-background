-- Sunset runner: layered mountains and a scrolling road, all generated.
return function(t, a)
  local c = {}; local function add(x) c[#c+1] = x end
  local function r(x,y,w,h,col) add(a.rect(x,y,w,h,col)) end
  local function l(x1,y1,x2,y2,col,w) add(a.line(x1,y1,x2,y2,col,w or 1)) end
  add(a.clear("#171b46"))
  local sky={"#25235b","#43276d","#71366f","#b64d69","#e8786a","#f5ae72","#f6cf83"}
  for i,col in ipairs(sky) do r(0,(i-1)*18,320,19,col) end
  r(232,39,34,34,"#ffe39a"); r(237,44,24,24,"#fff1b0")
  local m={0,116,35,83,70,111,106,74,148,112,190,78,235,115,270,91,320,116}
  for i=1,#m-2,2 do l(m[i],m[i+1],m[i+2],m[i+3],"#3a285d",3) end
  local m2={0,139,43,104,88,132,129,97,171,137,214,106,262,137,300,111,320,130}
  for i=1,#m2-2,2 do l(m2[i],m2[i+1],m2[i+2],m2[i+3],"#171b38",5) end
  r(0,156,320,24,"#0b102b")
  for x=-320,640,56 do r(x-((t*.35)%56),156,29,2,"#49325d") end
  for i=0,4 do local w=4+i*5; r(160-w/2,164+i*4,w,2,"#f6c875") end
  for y=0,178,2 do r(0,y,320,1,"#000000") end
  return c
end
