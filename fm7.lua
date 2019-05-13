-- FM7
--
-- FM polysynth
-- controlled by grid or MIDI and arc
--
-- enc 1: change presets
-- key 2: random modulation matrix
-- key 3: play a random note

local FM7 = require 'fm7/lib/fm7'
local tab = require 'tabutil'
local pattern_time = require 'pattern_time'
local UI = require 'ui'
local MusicUtil = require "musicutil"

tau = math.pi * 2
local g = grid.connect()
local a = arc.connect()
local keys_pressed = 0

local mode_transpose = 0
local root = { x=5, y=5 }
local trans = { x=5, y=5 }
local lit = {}
local encoder_mode = 1
local start_pos = {6,2}
local size = {6,6}
  
local screen_framerate = 15
local screen_refresh_metro

local MAX_NUM_VOICES = 16
-- current count of active voices
local nvoices = 0

engine.name = 'FM7'

-- pythagorean minor/major, kinda
local ratios = { 1, 9/8, 6/5, 5/4, 4/3, 3/2, 27/16, 16/9 }
local base = 27.5 -- low A

local function getHz(deg,oct)
  return base * ratios[deg] * (2^oct)
end

local function getHzET(note)
  hz = 55*2^(note/12)
  return hz
end

local function getEncoderMode()
  return encoder_mode
end

local function setEncoderMode(mode)
  encoder_mode = mode
end

local function draw_phase_matrix()
  for y = start_pos[2], (start_pos[2] + size[2] - 1) do
    for x = start_pos[1],(start_pos[1] + size[1] - 1) do
      g:led(x,y,3)
    end
  end  
end
  --[[
  Operator phase modulation matrix control for grid and arc
  Pick Any Four operators
  button press on grid performs the following sequence
  1. check if we are <= 4 else do nothing
  2. get current value from phase mod paramset
  3. draw value to Arc LED ring
  4. Enable Arc encoder to modulate parameter
  button release disables Arc ring

  --]]
arc_mapping = {"","","",""}

function grid_state(x,y,z)
  local op_out = x-start_pos[1]+1
  local op_in = y-start_pos[2]+1
  --print("setting arc control param to hz"..op_out.."_to_hz"..op_in)
  if z == 1 then
    if keys_pressed <= 4 then
      arc_mapping[keys_pressed] = "hz"..op_out.."_to_hz"..op_in
      a:segment(keys_pressed,0,params:get(arc_mapping[keys_pressed]),12)
      g:led(x,y,12)
    end
  else
    a:segment(keys_pressed+1,0,tau,0)
    g:led(x,y,3)
  end
end

function g.key(x,y,z)
  --print(keys_pressed, "keys pressed going in")
  if z == 1 then
    keys_pressed = keys_pressed + 1
    grid_state(x,y,z)
    end
  if z == 0 then
    keys_pressed = keys_pressed - 1
    --print("remove key "..x..","..y..": ",keys_pressed, "keys pressed")
    grid_state(x,y,z)
  end
  g:refresh()
  a:refresh()
end

local function light_arc(n,d)
  params:delta(arc_mapping[n], d/10)
  local val = params:get(arc_mapping[n])
  a:segment(n,0,val,12)
  a:refresh()
end

function a.delta(n,d)
  if n == 1 then
    light_arc(n,d)
  elseif n == 2 then
    light_arc(n,d)
  elseif n == 3 then
    light_arc(n,d)
  elseif n == 4 then
    light_arc(n,d)
  end
end

function init()
  m = midi.connect()
  m.event = midi_event
  
  pat = pattern_time.new()
  pat.process = grid_note_trans

  engine.amp(0.05)
  engine.stopAll()

  FM7.add_params()

  if g then gridredraw() end

  screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function(stage)
    redraw()
  end
  screen_refresh_metro:start(1 / screen_framerate)

  local startup_ani_count = 1
  local startup_ani_metro = metro.init()
  startup_ani_metro.event = function(stage)
    startup_ani_count = startup_ani_count + 1
  end
  startup_ani_metro:start( 0.1, 3 )
  ph_position,hz_position,amp_position = 0,0,0
  selected = {}
  mods = {}
  carriers = {}
  for m = 1,6 do
    selected[m] = {}
    mods[m] = {}
    carriers[m] = 0
    for n = 1,6 do
      selected[m][n] = 0
      mods[m][n] = 0
    end
  end
  light = 0
  number = 3
  
  pages = UI.Pages.new(1, 33)
end

--[[
function g.key(x, y, z)
  if x == 1 and (y > 2 and y < 8) then
    if z == 1 and getEncoderMode() == y - 1 then
      setEncoderMode(1)
    elseif z == 1 then
      setEncoderMode(y - 1) 
    end
  end

  if x == 1 then
    if z == 1 then
      if y == 1 and pat.rec == 0 then
        mode_transpose = 0
        trans.x = 5
        trans.y = 5
        pat:stop()
        engine.stopAll()
        pat:clear()
        pat:rec_start()
      elseif y == 1 and pat.rec == 1 then
        pat:rec_stop()
        if pat.count > 0 then
          root.x = pat.event[1].x
          root.y = pat.event[1].y
          trans.x = root.x
          trans.y = root.y
          pat:start()
        end
      elseif y == 2 and pat.play == 0 and pat.count > 0 then
        if pat.rec == 1 then
          pat:rec_stop()
        end
        pat:start()
      elseif y == 2 and pat.play == 1 then
        pat:stop()
        engine.stopAll()
        nvoices = 0
        lit = {}
      elseif y == 8 then
        mode_transpose = 1 - mode_transpose
      end
    end
  else
    if mode_transpose == 0 then
      local e = {}
      e.id = x*8 + y
      e.x = x
      e.y = y
      e.state = z
      pat:watch(e)
      grid_note(e)
    else
      trans.x = x
      trans.y = y
    end
  end
  gridredraw()
end
--]]

function grid_note(e)
  local note = ((7-e.y)*5) + e.x
  if e.state > 0 then
    if nvoices < MAX_NUM_VOICES then
      --engine.start(id, getHz(x, y-1))
      --print("grid > "..id.." "..note)
      engine.start(e.id, getHzET(note))
      lit[e.id] = {}
      lit[e.id].x = e.x
      lit[e.id].y = e.y
      nvoices = nvoices + 1
    end
  else
    if lit[e.id] ~= nil then
      engine.stop(e.id)
      lit[e.id] = nil
      nvoices = nvoices - 1
    end
  end
  gridredraw()
end

function grid_note_trans(e)
  local note = ((7-e.y+(root.y-trans.y))*5) + e.x + (trans.x-root.x)
  if e.state > 0 then
    if nvoices < MAX_NUM_VOICES then
      --engine.start(id, getHz(x, y-1))
      --print("grid > "..id.." "..note)
      engine.start(e.id, getHzET(note))
      lit[e.id] = {}
      lit[e.id].x = e.x + trans.x - root.x
      lit[e.id].y = e.y + trans.y - root.y
      nvoices = nvoices + 1
    end
  else
    engine.stop(e.id)
    lit[e.id] = nil
    nvoices = nvoices - 1
  end
  gridredraw()
end

local function toggleModLED(mode)
  if mode ~= 1 then
    g:led(1,mode + 1,12)
  end
end

function gridredraw()
  --[[
  g:all(0)
  g:led(1,1,2 + pat.rec * 10)
  g:led(1,2,2 + pat.play * 10)
  g:led(1,8,2 + mode_transpose * 10)
  toggleModLED(getEncoderMode())

  if mode_transpose == 1 then g:led(trans.x, trans.y, 4) end
  for i,e in pairs(lit) do
    g:led(e.x, e.y,15)
  end
  ]]--
  draw_phase_matrix()
  g:refresh()
end

function enc(n,delta)
  if n == 1 then
    pages:set_index_delta(delta, true)
    --print("set algo ".. (pages.index - 1))
    if (pages.index - 1) < 10 then
      params:read("/home/we/dust/code/fm7/data/fm7-0".. (pages.index - 1) .. ".pset")
    else
      params:read("/home/we/dust/code/fm7/data/fm7-".. (pages.index - 1) .. ".pset")
    end
  elseif n == 2 then
    print("encoder 2")

  elseif n == 3 then
    print("encoder 3")
  end
end

function key(n,z)
  if n == 2 and z== 1 then
    -- clear selected
    for x = 1,6 do
      for y = 1,6 do
        selected[x][y] = 0
        mods[x][y] = 0
        carriers[x] = 0
        params:set("hz"..x.."_to_hz"..y,mods[x][y])
      end
      params:set("carrier"..x,carriers[x])
    end
    
    -- choose new random mods
    for i = 1,number do
      x = math.random(6)
      y = math.random(6)
      selected[x][y] = 1
      mods[x][y] = 1 
      carriers[x] = 1
      params:set("hz"..x.."_to_hz"..y,mods[x][y])
      params:set("carrier"..x,carriers[x])
    end
  end
  redraw()
  if n == 3 then
    local note = ((7-math.random(8))*5) + math.random(16)
    if z == 1 then
      if nvoices < MAX_NUM_VOICES then
      --engine.start(id, getHz(x, y-1))
      --print("grid > "..id.." "..note)
        engine.start(0, getHzET(note))
        nvoices = nvoices + 1
      end
    else
      engine.stop(0)
      nvoices = nvoices - 1
    end
  end
end

local function draw_matrix_outputs()
  for m = 1,6 do
    for n = 1,6 do
      screen.rect(m*9, n*9, 9, 9)

      l = 2
      if selected[m][n] == 1 then
        l = l + 3 + light
      end
      screen.level(l)
      screen.move_rel(2, 6)
      screen.text(mods[m][n])
      screen.stroke()
    end
  end
  for m = 1,6 do
    screen.rect(80,m*9,9,9)
    screen.move_rel(12, 6)
    screen.text("out "..m)
    screen.move_rel(-32,0)
    screen.text(carriers[m])
    screen.stroke()    
  end  
end

local function draw_algo_rel(num)
    -- my first try was clever but not really intuitive.
    -- keeping it for posterity.
    screen.move(0,10)
    screen.text("algo "..num)
    local size = 9
    local x = 32
    local y = 5
    local spacing = 16
    local text_coords = {2,6}
    screen.rect(x,y,size,size)
    screen.move_rel(text_coords[1], text_coords[2])
    screen.text(6)
    y = y + spacing
    screen.rect(x,y,size,size)
    screen.move_rel(text_coords[1], text_coords[2])
    screen.text(5)
    y = y + spacing
    screen.rect(x,y,size,size)
    screen.move_rel(text_coords[1], text_coords[2])
    screen.text(4)
    y = y + spacing
    screen.rect(x,y,size,size)
    screen.move_rel(text_coords[1], text_coords[2])
    screen.text(3)
    x = x - spacing
    screen.rect(x,y,size,size)
    screen.move_rel(text_coords[1], text_coords[2])
    screen.text(1)
    y = y - spacing
    screen.rect(x,y,size,size)
    screen.move_rel(text_coords[1], text_coords[2])
    screen.text(2)
    screen.stroke()
end
local algo_box_coords = 
  {
--[[
absolute coords for operator box positions
 5|
21|
37|
53|__ __ __ __ __ ___
   32 48 64 80 96 112
   
    tuples in table are {x coord, y coord, connection_index,feedback_index}
--]]
    {{48,53,0,0},{48,37,1,0},{64,53,0,0},{64,37,3,0},{64,21,4,0},{64,5,5,6}},
    {{48,53,0,0},{48,37,1,2},{64,53,0,0},{64,37,3,0},{64,21,4,0},{64,5,5,0}},
    {{48,53,0,0},{48,37,1,0},{48,21,2,0},{64,53,0,0},{64,37,4,0},{64,21,5,6}},
    {{48,53,0,0},{48,37,1,0},{48,21,2,0},{64,53,0,6},{64,37,4,0},{64,21,5,0}},
    {{48,53,0,0},{48,37,1,0},{64,53,0,0},{64,37,3,0},{80,53,0,0},{80,37,5,6}},
    {{48,53,0,0},{48,37,1,0},{64,53,0,0},{64,37,3,0},{80,53,0,6},{80,37,5,0}},
    {{48,53,0,0},{48,37,1,0},{64,53,0,0},{64,37,3,0},{80,37,3,0},{80,21,5,6}},
    {{48,53,0,0},{48,37,1,0},{64,53,0,0},{64,37,3,4},{80,37,3,0},{80,21,5,0}},
    {{48,53,0,0},{48,37,1,2},{64,53,0,0},{64,37,3,0},{80,37,3,0},{80,21,5,0}},
    {{48,53,0,0},{48,37,1,0},{48,21,2,3},{64,53,0,0},{80,37,4,0},{64,37,4,0}},
    {{48,53,0,0},{48,37,1,0},{48,21,2,0},{64,53,0,0},{80,37,4,0},{64,37,4,6}},
    {{32,53,0,0},{32,37,1,2},{64,53,0,0},{48,37,3,0},{64,37,3,0},{80,37,3,0}},
    {{32,53,0,0},{32,37,1,0},{64,53,0,0},{48,37,3,0},{64,37,3,0},{80,37,3,6}},
    {{32,53,0,0},{32,37,1,0},{64,53,0,0},{64,37,3,0},{80,37,4,0},{64,21,4,6}},
    {{32,53,0,0},{32,37,1,2},{64,53,0,0},{64,37,3,0},{80,37,4,0},{64,21,4,0}},
    {{64,53,0,0},{48,37,1,0},{64,37,1,0},{64,21,3,0},{80,37,1,0},{80,21,5,6}},
    {{64,53,0,0},{48,37,1,2},{64,37,1,0},{64,21,3,0},{80,37,1,0},{80,21,5,0}},
    {{64,53,0,0},{48,37,1,0},{64,37,1,3},{80,37,1,0},{80,21,4,0},{80,5,5,0}},
    {{48,53,0,0},{48,37,1,0},{48,21,2,0},{64,53,0,0},{80,53,0,0},{64,37,{4,5},6}},
    {{32,53,0,0},{48,53,0,0},{32,37,{1,2},3},{80,53,0,0},{64,37,4,0},{80,37,4,0}},
    {{32,53,0,0},{48,53,0,0},{32,37,{1,2},3},{64,53,0,0},{80,53,0,0},{64,37,{4,5},0}},
    {{32,53,0,0},{32,37,1,0},{48,53,0,0},{64,53,0,0},{80,53,0,0},{64,37,{3,4,5},6}},
    {{32,53,0,0},{48,53,0,0},{48,37,3,0},{64,53,0,0},{80,53,0,0},{64,37,{4,5},6}},
    {{32,53,0,0},{48,53,0,0},{64,53,0,0},{80,53,0,0},{96,53,0,0},{80,37,{3,4,5},6}},
    {{32,53,0,0},{48,53,0,0},{64,53,0,0},{80,53,0,0},{96,53,0,0},{80,37,{4,5},6}},
    {{32,53,0,0},{48,53,0,0},{48,37,2,3},{80,53,0,0},{64,37,4,0},{80,37,4,0}},
    {{32,53,0,0},{48,53,0,0},{48,37,2,3},{80,53,0,0},{64,37,4,0},{80,37,4,0}},
    {{48,53,0,0},{48,37,1,0},{64,53,0,0},{64,37,3,0},{64,21,4,5},{80,53,0,0}},
    {{32,53,0,0},{48,53,0,0},{64,53,0,0},{64,37,3,0},{80,53,0,0},{80,37,5,6}},
    {{32,53,0,0},{48,53,0,0},{64,53,0,0},{64,37,3,0},{64,21,4,5},{80,53,0,0}},
    {{32,53,0,0},{48,53,0,0},{64,53,0,0},{80,53,0,0},{96,53,0,0},{96,37,5,6}},
    {{32,53,0,0},{48,53,0,0},{64,53,0,0},{80,53,0,0},{96,53,0,0},{112,53,0,6}}
  }

local function draw_algo(num)
    screen.move(0,10)
    screen.text("algo "..num)
    local size = 9
    local text_coords = {2,6}
  for a = 1,6 do
    local x = algo_box_coords[num][a][1]
    local y = algo_box_coords[num][a][2]
    local conn = algo_box_coords[num][a][3]
    local fb = algo_box_coords[num][a][4]
    if type(conn) == "number" then
      if conn > 0 then
        -- this is a line going down to the next box
        -- need a line going across to the next box
        -- and a line feedbacking to an arbitrary box
        screen.move(x+size/2,y+size)
        screen.line(x+size/2,y+16)
      end
    end
    screen.rect(x,y,size,size)
    screen.move_rel(text_coords[1], text_coords[2])
    screen.text(a)
    screen.stroke()
  end
end

function redraw()
  screen.clear()
  pages:redraw()
  
  if pages.index == 1 then
    draw_matrix_outputs()
  else
    draw_algo(pages.index - 1)
  end

  screen.update()
end

local function note_on(note, vel)
  if nvoices < MAX_NUM_VOICES then
    --engine.start(id, getHz(x, y-1))
    engine.start(note, MusicUtil.note_num_to_freq(note))
    nvoices = nvoices + 1
  end
end

local function note_off(note, vel)
  engine.stop(note)
  nvoices = nvoices - 1
end

function midi_event(data)
  if #data == 0 then return end
  local msg = midi.to_msg(data)

  -- Note off
  if msg.type == "note_off" then
    note_off(msg.note)

    -- Note on
  elseif msg.type == "note_on" then
    note_on(msg.note, msg.vel / 127)

--[[
    -- Key pressure
  elseif msg.type == "key_pressure" then
    set_key_pressure(msg.note, msg.val / 127)

    -- Channel pressure
  elseif msg.type == "channel_pressure" then
    set_channel_pressure(msg.val / 127)

    -- Pitch bend
  elseif msg.type == "pitchbend" then
    local bend_st = (util.round(msg.val / 2)) / 8192 * 2 -1 -- Convert to -1 to 1
    local bend_range = params:get("bend_range")
    set_pitch_bend(bend_st * bend_range)

  ]]--
  end
end

function cleanup()
  pat:stop()
  pat = nil
end
