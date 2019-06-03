-- FM7 Polyphonic Synthesizer
-- With 6 Operator Frequency 
-- Modulation
-- ///////////////////////////
-- key 2: random phase mods
-- key 3: play a random note
-- ///////////////////////////
-- grid pattern player:
-- 1-16 1 high voice
-- 1-16 8 low voice
-- 16 2 pattern record toggle
-- 16 3 pattern play toggle
-- 16 7 pattern transpose mode
-- ///////////////////////////
-- 1-6 2-7 phase mod matrix
-- 8 2-7 operator audio output
-- 10 2-7 frequency multiplier
-- (enables encoder control)
-- ENC1 coarse, ENC2 fine
-- ///////////////////////////
-- Arc encoders are assigned 
-- when phase mod toggled.
-- Without an arc, ENC3 is 
-- phase mod controller

engine.name = 'FM7'
tau = math.pi * 2
arc_mapping = {{0,0,"none"},{0,0,"none"},{0,0,"none"},{0,0,"none"}}
enc_mapping = {true,false,false} -- table to hold parameter names for Norns encoders
g = grid.connect()
a = arc.connect()

local FM7 = require 'fm7/lib/fm7'
local tab = require 'tabutil'
local pattern_time = require 'pattern_time'
local UI = require 'ui'
local MusicUtil = require "musicutil"
local mode_transpose = 0
local root = { x=5, y=5 }
local trans = { x=5, y=5 }
local lit = {}
-- top right button to start drawing our grid
local start_pos = {1,2}
local size = {6,6}
local MAX_NUM_VOICES = 16
-- current count of active voices
local nvoices = 0
local toggles = {}
local ph_position,hz_position,amp_position = 0,0,0
local selected = {}
local mods = {}
local carriers = {}
local phase_keys_pressed = 0
local phase_max_keys = 1
local screen_framerate = 15
local screen_refresh_metro

-- pythagorean minor/major, kinda
local ratios = { 1, 9/8, 6/5, 5/4, 4/3, 3/2, 27/16, 16/9 }
local base = 27.5 -- low A

-- ### SO MANY FUNCTIONS ### --
local function getHz(deg,oct)
  return base * ratios[deg] * (2^oct)
end

local function getHzET(note)
  hz = 55*2^(note/12)
  return hz
end

local function draw_phase_matrix()
  for y = start_pos[2], (start_pos[2] + size[2] - 1) do
    for x = start_pos[1],(start_pos[1] + size[1] - 1) do
      g:led(x,y,3)
    end
  end  
end

local function draw_output_vector()
  local x = start_pos[1] + size[1] + 1
  local y = start_pos[2]
  for i = y,size[2]+1 do
    g:led(x,i,10)
  end
end

local function draw_frequency_vector()
  local x = start_pos[1] + size[1] + 3
  local y = start_pos[2]
  for i = y,size[2]+1 do
    g:led(x,i,3)
  end
end

local function grid_vector(x,y)
  return (x-start_pos[1]+1) + ((y-start_pos[2]) * size[1])
end

local function get_toggles_value(x,y)
  idx = grid_vector(x,y)
  return toggles[idx]
end

local function set_toggles_value(x,y,val)
  idx = grid_vector(x,y)
  toggles[idx] = val
end

local function bool_to_int(value)
  return value and 1 or 0
end

local function assign_next_arc_enc()
  enc = 0
  for i=1,4 do
    if arc_mapping[i][2] == 0 then
      arc_mapping[i][2] = i
      enc = i
      break
    end
  end
  return enc
end

local function remove_arc_enc(x,y)
  vec = grid_vector(x,y)
  for i=1,4 do
    if vec == arc_mapping[i][1] then
      a:segment(arc_mapping[i][2],0,tau,0)
      arc_mapping[i] = {0,0,"none"}
    end
  end
end

local function grid_phase_state(x,y,z)
  local op_out = x-start_pos[1]+1
  local op_in = y-start_pos[2]+1
  local toggle = get_toggles_value(x,y)
  if z == 1 then
    toggle = not toggle
    set_toggles_value(x,y,toggle)
      if toggle then
        if phase_max_keys > 1 then
          local arc_enc = assign_next_arc_enc()
          arc_mapping[arc_enc] = {grid_vector(x,y),arc_enc,"hz"..op_out.."_to_hz"..op_in}
          a:segment(arc_mapping[arc_enc][2],0,params:get(arc_mapping[arc_enc][3]),12)
        else
          enc_mapping[3] = "hz"..op_out.."_to_hz"..op_in
        end
      else
        remove_arc_enc(x,y)
        enc_mapping[3] = false
      end
    local s = bool_to_int(toggle)
    g:led(x,y,3+s*9)
  end
end

local function output_vector_state(x,y,z)
  idx = y - 1
  if carriers[idx] ~= 1 then
    carriers[idx] = 1
  else
    carriers[idx] = 0
  end
  params:set("carrier"..idx, carriers[idx])
  g:led(x,y,3+carriers[idx]*9)
end

local function frequency_vector_state(x,y,z)
  if z == 1 then
    enc_mapping[2] = "hz"..y - start_pos[2] + 1
  else
    enc_mapping[2] = false
  end
  --tab.print(enc_mapping)
  g:led(x,y,3+z*12)
end

function g.key(x,y,z)
  -- phase mod matrix updates
  if x < (start_pos[1] + size[1]) and y >= start_pos[2] and y < (start_pos[2] + size[2]) then
    if phase_keys_pressed <= phase_max_keys then
      if z == 1 and get_toggles_value(x,y) then
        phase_keys_pressed = phase_keys_pressed -1
        grid_phase_state(x,y,z)
      elseif z == 1 and phase_keys_pressed ~= phase_max_keys then
        phase_keys_pressed = phase_keys_pressed + 1
        grid_phase_state(x,y,z)
      end
    end
  elseif x == (start_pos[1] + size[1] + 1) and y >= start_pos[2] and y < (start_pos[2] + size[2]) then
    if z == 1 then
      output_vector_state(x,y,z)
    end
  elseif x == (start_pos[1] + size[1] + 3) and y >= start_pos[2] and y < (start_pos[2] + size[2]) then
    frequency_vector_state(x,y,z)
  end
  g:refresh()
  a:refresh()
  pattern_control(x,y,z)
end

local function arc_encoder_is_assigned(n)
  result = false
  for i=1,4 do
    if arc_mapping[i][2] == n then
      result = true
    end
  end
  return result
end

local function update_phase_matrix(n,d)
  if arc_encoder_is_assigned(n) then
    params:delta(arc_mapping[n][3], d/10)
    local val = params:get(arc_mapping[n][3])
    a:segment(n,0,val,12)
    local screen_val = math.ceil(val)
    local x = (arc_mapping[n][1] % size[1]) == 0 and size[1] or arc_mapping[n][1] % size[1]
    local y = math.ceil(arc_mapping[n][1] / size[2])
    mods[x][y] = screen_val
    redraw()
    a:refresh()
  elseif enc_mapping[3] then
    params:delta(enc_mapping[3],d/2)
    local screen_val = math.ceil(params:get(enc_mapping[3]))
    idx = tab.key(toggles,true)
    local x = (idx % size[1]) == 0 and size[1] or idx % size[1]
    local y = math.ceil(idx / size[2])
    mods[x][y] = screen_val
    redraw()    
  end
end

function a.delta(n,d)
  if n == 1 then
    update_phase_matrix(n,d)
  elseif n == 2 then
    update_phase_matrix(n,d)
  elseif n == 3 then
    update_phase_matrix(n,d)
  elseif n == 4 then
    update_phase_matrix(n,d)
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

  if g then 
    draw_phase_matrix()
    draw_output_vector()
    draw_frequency_vector()
    gridredraw()
  end
  
  if a.device then phase_max_keys = 4 end

  screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function(stage)
    redraw()
  end
  screen_refresh_metro:start(1 / screen_framerate)

  for m = 1,6 do
    selected[m] = {}
    mods[m] = {}
    carriers[m] = 1
    for n = 1,6 do
      selected[m][n] = 0
      mods[m][n] = 0
    end
  end
  light = 0
  number = 3
-- fill up our toggle table with false values
  for i=1,6*6 do
    table.insert(toggles,false)
  end

  pages = UI.Pages.new(1, 1)
end

function pattern_control(x, y, z)
  if x == 16 and y > 1 and y < 8 then
    if z == 1 then
      if y == 2 and pat.rec == 0 then
        mode_transpose = 0
        trans.x = 5
        trans.y = 5
        pat:stop()
        engine.stopAll()
        pat:clear()
        pat:rec_start()
      elseif y == 2 and pat.rec == 1 then
        pat:rec_stop()
        if pat.count > 0 then
          root.x = pat.event[1].x
          root.y = pat.event[1].y
          trans.x = root.x
          trans.y = root.y
          pat:start()
        end
      elseif y == 3 and pat.play == 0 and pat.count > 0 then
        if pat.rec == 1 then
          pat:rec_stop()
        end
        pat:start()
      elseif y == 3 and pat.play == 1 then
        pat:stop()
        engine.stopAll()
        nvoices = 0
        lit = {}
      elseif y == 7 then
        mode_transpose = 1 - mode_transpose
      end
    end
  -- catch key events outside the control row
  elseif y < 2 or y > 7 then
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

function grid_note(e)
  local note = ((7-e.y)*5) + e.x
  if e.state > 0 then
    if nvoices < MAX_NUM_VOICES then
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

function gridredraw()
  -- clear the LEDs on the top and bottom rows
  for i=1,16 do
    g:led(i,1,0)
    g:led(i,8,0)
  end
  g:led(16,2,2 + pat.rec * 10)
  g:led(16,3,2 + pat.play * 10)
  g:led(16,7,2 + mode_transpose * 10)

  if mode_transpose == 1 then g:led(trans.x, trans.y, 4) end
  -- look into our table of lights and light up the notes
  for i,e in pairs(lit) do
    g:led(e.x, e.y,15)
  end
  g:refresh()
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
    screen.rect(75,m*9,9,9)
    screen.move_rel(2, 6)
    screen.text(carriers[m])
    screen.rect(95,m*9,24,9)
    screen.move_rel(2, 6)
    screen.text(params:get("hz"..m))
    screen.stroke()    
  end  
end

function enc(n,delta)
  if n == 1 then
    params:delta(enc_mapping[2],delta/4)
    draw_matrix_outputs()
  elseif n == 2 then
    params:delta(enc_mapping[2],delta/10)
    draw_matrix_outputs()
  elseif n == 3 then
    update_phase_matrix(n,delta)
  end
end

local function set_random_phase_mods(n)
    -- clear selected
    for x = 1,6 do
      for y = 1,6 do
        selected[x][y] = 0
        mods[x][y] = 0
        params:set("hz"..x.."_to_hz"..y,mods[x][y])
        g:led(x,y+1,3)
      end
    end
    
    -- choose new random mods
    for i = 1,n do
      x = math.random(6)
      y = math.random(6)
      selected[x][y] = 1
      mods[x][y] = 1 
      params:set("hz"..x.."_to_hz"..y,mods[x][y])
      grid_phase_state(x,y+1,1)
    end
end

function key(n,z)
  if n == 2 and z== 1 then
    set_random_phase_mods(number)
    redraw()
    gridredraw()
  end
  if n == 3 then
    local note = ((7-math.random(8))*5) + math.random(16)
    if z == 1 then
      if nvoices < MAX_NUM_VOICES then
        engine.start(0, getHzET(note))
        nvoices = nvoices + 1
      end
    else
      engine.stop(0)
      nvoices = nvoices - 1
    end
  end
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
  draw_matrix_outputs()
    
  --[[
  if pages.index == 1 then
    draw_matrix_outputs()
  else
    draw_algo(pages.index - 1)
  end
  --]]
  
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
