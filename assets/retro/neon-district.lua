-- Neon district: an Amiga demo-style city with a moving horizon grid.
return function(t, a)
  local c={}; local function add(x)c[#c+1]=x end
  local function r(x,y,w,h,col)add(a.rect(x,y,w,h,col))end
  add(a.clear("#080d25"))
  for i=0,5 do r(0,i*20,320,21,({"#080d25","#11133b","#191752","#29185d","#441d69","#68266f"})[i+1]) end
  for i=1,34 do local x=(i*73)%320; local y=(i*31)%105; r(x,y,1+i%2,1+i%2,i%3==0 and "#f58ad7" or "#54e0d0") end
  local b={{0,82,39,"#182057"},{43,58,76,"#20256c"},{80,91,115,"#171b4c"},{119,47,151,"#27266e"},{155,72,190,"#1b2057"},{194,39,229,"#29246d"},{233,68,270,"#172052"},{274,52,320,"#25205f"}}
  for q,v in ipairs(b) do
    r(v[1],v[2],v[3]-v[1],57,v[4])
    for y=v[2]+10,130,13 do for x=v[1]+7,v[3]-3,12 do if (x+y+q)%3~=0 then r(x,y,4,3,q%2==0 and "#49daca" or "#e65fba") end end end
  end
  r(0,139,320,41,"#0b102d")
  for x=-320,640,32 do r(x-((t*1.2)%32),151,18,2,"#e65fba") end
  for y=145,180,9 do r(0,y,320,1,"#17234b") end
  return c
end
