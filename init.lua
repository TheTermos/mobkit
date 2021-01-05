-- yaw values:
-- x+ = -pi/2
-- x- = +pi/2
-- z+ = 0
-- z- = -pi

mobkit={}

mobkit.gravity = -9.8
mobkit.friction = 0.4	-- less is more

local abs = math.abs
local pi = math.pi
local floor = math.floor
local ceil = math.ceil
local random = math.random
local sqrt = math.sqrt
local max = math.max
local min = math.min
local tan = math.tan
local pow = math.pow

local sign = function(x)
	return (x<0) and -1 or 1
end

mobkit.terminal_velocity = sqrt(2*-mobkit.gravity*20) -- 20 meter fall = dead
mobkit.safe_velocity = sqrt(2*-mobkit.gravity*5) -- 5 m safe fall

local abr = tonumber(minetest.get_mapgen_setting('active_block_range')) or 3
	
-- UTILITY FUNCTIONS

function mobkit.dot(v1,v2)
	return v1.x*v2.x+v1.y*v2.y+v1.z*v2.z
end

function mobkit.minmax(v,m)
	return min(abs(v),m)*sign(v)
end

function mobkit.pos_shift(pos,vec) -- vec components can be omitted e.g. vec={y=1}
	vec.x=vec.x or 0
	vec.y=vec.y or 0
	vec.z=vec.z or 0
	return {x=pos.x+vec.x,
			y=pos.y+vec.y,
			z=pos.z+vec.z}
end

function mobkit.pos_translate2d(pos,yaw,dist) -- translate pos dist distance in yaw direction
	return vector.add(pos,vector.multiply(minetest.yaw_to_dir(yaw),dist))
end

function mobkit.is_pos_in_box(pos,bpos,box)
	return pos.x > bpos.x+box[1] and pos.x < bpos.x+box[4] and
			pos.y > bpos.y+box[2] and pos.y < bpos.y+box[5] and
			pos.z > bpos.z+box[3] and pos.z < bpos.z+box[6]
end

-- call this instead if you want feet position.
--[[
function mobkit.get_stand_pos(thing)	-- thing can be luaentity or objectref.
	if type(thing) == 'table' then
		return mobkit.pos_shift(thing.object:get_pos(),{y=thing.collisionbox[2]+0.01})
	elseif type(thing) == 'userdata' then
		local colbox = thing:get_properties().collisionbox
		return mobkit.pos_shift(thing:get_pos(),{y=colbox[2]+0.01})
	end
end	--]]

function mobkit.get_stand_pos(thing)	-- thing can be luaentity or objectref.
	local pos = {}
	local colbox = {}
	if type(thing) == 'table' then
		pos = thing.object:get_pos()
		colbox = thing.object:get_properties().collisionbox
	elseif type(thing) == 'userdata' then
		pos = thing:get_pos()
		colbox = thing:get_properties().collisionbox
	else 
		return false
	end
	return mobkit.pos_shift(pos,{y=colbox[2]+0.01}), pos
end

function mobkit.set_acceleration(thing,vec,limit)
	limit = limit or 100
	if type(thing) == 'table' then thing=thing.object end
	vec.x=mobkit.minmax(vec.x,limit)
	vec.y=mobkit.minmax(vec.y,limit)
	vec.z=mobkit.minmax(vec.z,limit)
	
	thing:set_acceleration(vec)
end

function mobkit.nodeatpos(pos)
	local node = minetest.get_node_or_nil(pos)
	if node then return minetest.registered_nodes[node.name] end
end

function mobkit.get_nodename_off(pos,vec)
	return minetest.get_node(mobkit.pos_shift(pos,vec)).name
end

function mobkit.get_node_pos(pos)
	return  {
			x=floor(pos.x+0.5),
			y=floor(pos.y+0.5),
			z=floor(pos.z+0.5),
			}
end

function mobkit.get_nodes_in_area(pos1,pos2,full)
	local npos1=mobkit.get_node_pos(pos1)
	local npos2=mobkit.get_node_pos(pos2)
	local result = {}
	local cnt = 0	-- safety
	
	local sx = (pos2.x<pos1.x) and -1 or 1
	local sz = (pos2.z<pos1.z) and -1 or 1
	local sy = (pos2.y<pos1.y) and -1 or 1
	
	local x=npos1.x-sx
	local z=npos1.z-sz
	local y=npos1.y-sy
	
	repeat
		x=x+sx
		z=npos1.z-sz
		repeat
			z=z+sz
			y=npos1.y-sy
			repeat
				y=y+sy
				
				local pos = {x=x,y=y,z=z}
				local node = mobkit.nodeatpos(pos)
				if node	then
					if full==true then
						result[pos] = node
					else
						result[node] = true
					end
				end
			
				cnt=cnt+1
				if cnt > 125 then 
					minetest.chat_send_all('get_nodes_in_area: area too big ')
					return result
				end
			
			until y==npos2.y
		until z==npos2.z
	until x==npos2.x
	
	return result
end

function mobkit.get_hitbox_bottom(self)
	local y = self.collisionbox[2]
	local pos = self.object:get_pos()
	return {
			{x=pos.x+self.collisionbox[1],y=pos.y+y,z=pos.z+self.collisionbox[3]},
			{x=pos.x+self.collisionbox[1],y=pos.y+y,z=pos.z+self.collisionbox[6]},
			{x=pos.x+self.collisionbox[4],y=pos.y+y,z=pos.z+self.collisionbox[3]},
			{x=pos.x+self.collisionbox[4],y=pos.y+y,z=pos.z+self.collisionbox[6]},
		}
end
		
function mobkit.get_node_height(pos)
	local npos = mobkit.get_node_pos(pos)
	local node = mobkit.nodeatpos(npos)
	if node == nil then return nil end
	
	if node.walkable then
		if node.drawtype == 'nodebox' then
			if node.node_box and node.node_box.type == 'fixed' then
				if type(node.node_box.fixed[1]) == 'number' then
					return npos.y + node.node_box.fixed[5] ,0, false
				elseif type(node.node_box.fixed[1]) == 'table' then
					return npos.y + node.node_box.fixed[1][5] ,0, false
				else
					return npos.y + 0.5,1, false			-- todo handle table of boxes
				end		
			elseif node.node_box and node.node_box.type == 'leveled' then
				return minetest.get_node_level(pos)/64-0.5+mobkit.get_node_pos(pos).y, 0, false
			else
				return npos.y + 0.5,1, false	-- the unforeseen
			end
		else
			return npos.y+0.5,1, false	-- full node
		end
	else
		local liquidflag = false
		if node.drawtype == 'liquid' then liquidflag = true end
		return npos.y-0.5,-1,liquidflag	
	end
end

-- get_terrain_height
-- steps(optional) number of recursion steps; default=3
-- dir(optional) is 1=up, -1=down, 0=both; default=0
-- liquidflag(forbidden) never provide this parameter.
function mobkit.get_terrain_height(pos,steps,dir,liquidflag) --dir is 1=up, -1=down, 0=both 
	steps = steps or 3
	dir = dir or 0

	local h,f,l = mobkit.get_node_height(pos)
	if h == nil then return nil end
	if l then liquidflag = true end
	
	if f==0 then 
		return h, liquidflag
	end
	
	if dir==0 or dir==f then
		steps = steps - 1
		if steps <=0 then return nil end
		return mobkit.get_terrain_height(mobkit.pos_shift(pos,{y=f}),steps,f,liquidflag)
	else
		return h, liquidflag
	end
end

function mobkit.get_spawn_pos_abr(dtime,intrvl,radius,chance,reduction)
	dtime = min(dtime,0.1)
	local plyrs = minetest.get_connected_players()
	intrvl=1/intrvl

	if random()<dtime*(intrvl*#plyrs) then
		local plyr = plyrs[random(#plyrs)]		-- choose random player
		local vel = plyr:get_player_velocity()
		local spd = vector.length(vel)
		chance = (1-chance) * 1/(spd*0.75+1)
		
		local yaw
		if spd > 1 then
			-- spawn in the front arc
			yaw = minetest.dir_to_yaw(vel) + random()*0.35 - 0.75
		else
			-- random yaw
			yaw = random()*pi*2 - pi
		end
		local pos = plyr:get_pos()
		local dir = vector.multiply(minetest.yaw_to_dir(yaw),radius)
		local pos2 = vector.add(pos,dir)
		pos2.y=pos2.y-5
		local height, liquidflag = mobkit.get_terrain_height(pos2,32)
		if height then
			local objs = minetest.get_objects_inside_radius(pos,radius*1.1)
			for _,obj in ipairs(objs) do				-- count mobs in abrange
				if not obj:is_player() then
					local lua = obj:get_luaentity()
					if lua and lua.name ~= '__builtin:item' then
						chance=chance + (1-chance)*reduction	-- chance reduced for every mob in range
					end
				end
			end
			if chance < random() then
				pos2.y = height
				objs = minetest.get_objects_inside_radius(pos2,radius*0.95)
				for _,obj in ipairs(objs) do				-- do not spawn if another player around
					if obj:is_player() then return end
				end
				return pos2, liquidflag
			end
		end
	end
end

function mobkit.turn2yaw(self,tyaw,rate)
	tyaw = tyaw or 0 --temp
	rate = rate or 6
		local yaw = self.object:get_yaw()
		yaw = yaw+pi
		tyaw=(tyaw+pi)%(pi*2)
		
		local step=min(self.dtime*rate,abs(tyaw-yaw)%(pi*2))
		
		local dir = abs(tyaw-yaw)>pi and -1 or 1
		dir = tyaw>yaw and dir*1 or dir * -1
		
		local nyaw = (yaw+step*dir)%(pi*2)
		self.object:set_yaw(nyaw-pi)
		
		if nyaw==tyaw then return true, nyaw-pi
		else return false, nyaw-pi end
end

function mobkit.dir_to_rot(v,rot)
	rot = rot or {x=0,y=0,z=0}
	return {x = (v.x==0 and v.y==0 and v.z==0) and rot.x or math.atan2(v.y,vector.length({x=v.x,y=0,z=v.z})),
			y = (v.x==0 and v.z==0) and rot.y or minetest.dir_to_yaw(v),
			z=rot.z}
end

function mobkit.rot_to_dir(rot) -- keep rot within <-pi/2,pi/2>
	local dir = minetest.yaw_to_dir(rot.y)
	dir.y = dir.y+tan(rot.x)*vector.length(dir)
	return vector.normalize(dir)
end

function mobkit.isnear2d(p1,p2,thresh)
	if abs(p2.x-p1.x) < thresh and abs(p2.z-p1.z) < thresh then
		return true
	else
		return false
	end
end

-- object has reached the destination if dest is in the rear half plane.
function mobkit.is_there_yet2d(pos,dir,dest) -- obj positon; facing vector; destination position

	local c = -dir.x*pos.x-dir.z*pos.z						-- the constant		
	
	if dir.z > 0 then		
		return dest.z <= (-dir.x*dest.x - c)/dir.z			-- line equation
	elseif dir.z < 0 then
		return dest.z >= (-dir.x*dest.x - c)/dir.z
	elseif dir.x > 0 then
		return dest.x <= (-dir.z*dest.z - c)/dir.x
	elseif dir.x < 0 then
		return dest.x >= (-dir.z*dest.z - c)/dir.x
	else
		return false
	end
	
end

function mobkit.isnear3d(p1,p2,thresh)
	if abs(p2.x-p1.x) < thresh and abs(p2.z-p1.z) < thresh and abs(p2.y-p1.y) < thresh then
		return true
	else
		return false
	end
end

function mobkit.get_box_intersect_cols(pos,box)
	local pmin = {x=floor(pos.x+box[1]+0.5),z=floor(pos.z+box[3]+0.5)}
	local pmax = {x=floor(pos.x+box[4]+0.5),z=floor(pos.z+box[6]+0.5)}
	
	result= {}
	for x=pmin.x,pmax.x do
		for z=pmin.z,pmax.z do
			table.insert(result,{x=x,z=z})
		end
	end
	return result
end

function mobkit.get_box_displace_cols(pos,box,vec,dist)

	local result = {}
	-- front facing corner pos and neighbors
	local fpos = {pos.y}
	local xpos={pos.y}
	local zpos={pos.y}
	local xoff=nil
	local zoff=nil
	
	if vec.x < 0 then
		fpos.x = pos.x+box[1]	-- frontmost corner's x
		xoff = box[4]-box[1]	-- edge offset along x
	else
		fpos.x = pos.x+box[4]
		xoff = box[1]-box[4]
	end
	
	if vec.z < 0 then
		fpos.z = pos.z+box[3]	-- frontmost corner's z
		zoff = box[6]-box[3]	-- edge offset along z
	else
		fpos.z = pos.z+box[6]
		zoff = box[3]-box[6]
	end
	
	-- displacement vector
	if dist then vec = vector.multiply(vector.normalize(vec),dist) end
	
		-- traverse x
	local xsgn = sign(vec.x)
	local zsgn = sign(zoff)
	local counter=0
	for x = floor(fpos.x+0.5)+xsgn*0.5, fpos.x+vec.x, xsgn do
		local zcomp = vec.x == 0 and 0 or fpos.z + (x-fpos.x)*vec.z/vec.x	-- z component at the intersection of x and node edge
		for z = floor(zcomp+0.5), floor(zcomp+zoff+0.5), zsgn do
			counter=counter+1
			if counter > 50 then return result end
			table.insert(result,{x=x+xsgn*0.5,z=z})
		end
	end
	
			-- traverse z
	local zsgn = sign(vec.z)
	local xsgn = sign(xoff)
	counter=0
	for z = floor(fpos.z + 0.5)+zsgn*0.5, fpos.z+vec.z, zsgn do
		local xcomp = vec.z == 0 and 0 or fpos.x + (z-fpos.z)*vec.x/vec.z
		for x = floor(xcomp+0.5), floor(xcomp+xoff+0.5), xsgn do
			counter=counter+1
			if counter > 50 then return result end
			table.insert(result,{x=x,z=z+zsgn*0.5})
		end
	end
	
	return result
end

function mobkit.get_box_height(thing)
	if type(thing) == 'table' then thing = thing.object end
	local colbox = thing:get_properties().collisionbox
	local height
	if colbox then height = colbox[5]-colbox[2] 
	else height = 0.1 end
	
	return height > 0 and height or 0.1
end

function mobkit.is_alive(thing)		-- thing can be luaentity or objectref.
--	if not thing then return false end
	if not mobkit.exists(thing) then return false end
	if type(thing) == 'table' then return thing.hp > 0 end
	if thing:is_player() then return thing:get_hp() > 0
	else 
		local lua = thing:get_luaentity()
		local hp = lua and lua.hp or nil
		return hp and hp > 0
	end
end

function mobkit.exists(thing)
	if not thing then return false end
	if type(thing) == 'table' then thing=thing.object end
	if type(thing) == 'userdata' then 
		if thing:is_player() then
			if thing:get_look_horizontal() then return true end 
		else
			if thing:get_yaw() then return true end
		end
	end
end

function mobkit.hurt(luaent,dmg)
	if not luaent then return false end
	if type(luaent) == 'table' then
		luaent.hp = max((luaent.hp or 0) - dmg,0)
	end
end

function mobkit.heal(luaent,dmg)
	if not luaent then return false end
	if type(luaent) == 'table' then
		luaent.hp = min(luaent.max_hp,(luaent.hp or 0) + dmg)
	end
end

function mobkit.animate(self,anim)
	if self.animation and self.animation[anim] then
		if self._anim == anim then return end
		self._anim=anim
		
		local aparms = {}
		if #self.animation[anim] > 0 then
			aparms = self.animation[anim][random(#self.animation[anim])]
		else
			aparms = self.animation[anim]
		end
		
		aparms.frame_blend = aparms.frame_blend or 0
		
		self.object:set_animation(aparms.range,aparms.speed,aparms.frame_blend,aparms.loop)
	else
		self._anim = nil
	end
end

function mobkit.make_sound(self, sound)
	local spec = self.sounds and self.sounds[sound]
	local param_table = {object=self.object}
	
	if type(spec) == 'table' then
		--pick random sound if it's a spec for random sounds
		if #spec > 0 then spec = spec[random(#spec)] end
		
		--returns value or a random value within the range [value[1], value[2])
		local function in_range(value)
			return type(value) == 'table' and value[1]+random()*(value[2]-value[1]) or value
		end
		
		--pick random values within a range if they're a table
		param_table.gain = in_range(spec.gain)
		param_table.fade = in_range(spec.fade)
		param_table.pitch = in_range(spec.pitch)
		return minetest.sound_play(spec.name, param_table)
	end
	return minetest.sound_play(spec, param_table)
end

function mobkit.go_forward_horizontal(self,speed)	-- sets velocity in yaw direction, y component unaffected
	local y = self.object:get_velocity().y
	local yaw = self.object:get_yaw()
	local vel = vector.multiply(minetest.yaw_to_dir(yaw),speed)
	vel.y = y
	self.object:set_velocity(vel)
end

function mobkit.drive_to_pos(self,tpos,speed,turn_rate,dist) 
	local pos=self.object:get_pos()
	dist = dist or 0.2
	if mobkit.isnear2d(pos,tpos,dist) then return true end
	local tyaw = minetest.dir_to_yaw(vector.direction(pos,tpos))
	mobkit.turn2yaw(self,tyaw,turn_rate)
	mobkit.go_forward_horizontal(self,speed)
	return false
end

function mobkit.timer(self,s) -- returns true approx every s seconds
	local t1 = floor(self.time_total)
	local t2 = floor(self.time_total+self.dtime)
	if t2>t1 and t2%s==0 then return true end
end

-- Memory functions. 
-- Stuff in memory is serialized, never try to remember objectrefs.
function mobkit.remember(self,key,val)
	self.memory[key]=val
	return val
end

function mobkit.forget(self,key)
	self.memory[key] = nil
end

function mobkit.recall(self,key)
	return self.memory[key]
end

-- Queue functions
function mobkit.queue_high(self,func,priority)
	local maxprty = mobkit.get_queue_priority(self)
	if priority > maxprty then
		mobkit.clear_queue_low(self)
	end

	for i,f in ipairs(self.hqueue) do
		if priority > f.prty then
			table.insert(self.hqueue,i,{func=func,prty=priority})
			return
		end
	end
	table.insert(self.hqueue,{func=func,prty=priority})
end

function mobkit.queue_low(self,func)
	table.insert(self.lqueue,func)
end

function mobkit.is_queue_empty_low(self)
	if #self.lqueue == 0 then return true
	else return false end
end

function mobkit.clear_queue_high(self)
	self.hqueue = {}
end

function mobkit.clear_queue_low(self)
	self.lqueue = {}
end

function mobkit.get_queue_priority(self)
	if #self.hqueue > 0 then
		return self.hqueue[1].prty
	else return 0 end
end

function mobkit.is_queue_empty_high(self)
	if #self.hqueue == 0 then return true
	else return false end
end

function mobkit.get_nearby_player(self)	-- returns random player if nearby or nil
	for _,obj in ipairs(self.nearby_objects) do
		if obj:is_player() and mobkit.is_alive(obj) then return obj end
	end
	return
end

function mobkit.get_nearby_entity(self,name)	-- returns random nearby entity of name or nil
	for _,obj in ipairs(self.nearby_objects) do
		if mobkit.is_alive(obj) and not obj:is_player() and obj:get_luaentity().name == name then return obj end
	end
	return
end

function mobkit.get_closest_entity(self,name)	-- returns closest entity of name or nil
	local cobj = nil
	local dist = abr*64
	local pos = self.object:get_pos()
	for _,obj in ipairs(self.nearby_objects) do
		local luaent = obj:get_luaentity()
		if mobkit.is_alive(obj) and not obj:is_player() and luaent and luaent.name == name then
			local opos = obj:get_pos()
			local odist = abs(opos.x-pos.x) + abs(opos.z-pos.z)
			if odist < dist then
				dist=odist
				cobj=obj
			end
		end
	end
	return cobj
end

local function execute_queues(self)
	--Execute hqueue
	if #self.hqueue > 0 then
		local func = self.hqueue[1].func
		if func(self) then
			table.remove(self.hqueue,1)
			self.lqueue = {}
		end
	end
	-- Execute lqueue
	if #self.lqueue > 0 then
		local func = self.lqueue[1]
		if func(self) then
			table.remove(self.lqueue,1)
		end
	end
end

local function sensors()
	local timer = 2
	local pulse = 1
	return function(self)
		timer=timer-self.dtime
		if timer < 0 then
		
			pulse = pulse + 1				-- do full range every third scan
			local range = self.view_range
			if pulse > 2 then 
				pulse = 1
			else
				range = self.view_range*0.5
			end
			
			local pos = self.object:get_pos()
--local tim = minetest.get_us_time()
			self.nearby_objects = minetest.get_objects_inside_radius(pos, range)
--minetest.chat_send_all(minetest.get_us_time()-tim)
			for i,obj in ipairs(self.nearby_objects) do	
				if obj == self.object then
					table.remove(self.nearby_objects,i)
					break
				end
			end
			timer=2
		end
	end
end

------------
-- CALLBACKS
------------

function mobkit.default_brain(self)
	if mobkit.is_queue_empty_high(self) then mobkit.hq_roam(self,0) end
end

function mobkit.physics(self)
	local vel=self.object:get_velocity()
	local vnew = vector.new(vel)
		-- dumb friction
		
	if self.isonground and not self.isinliquid then
		vnew = {x= vel.x> 0.2 and vel.x*mobkit.friction or 0,
				y=vel.y,
				z=vel.z > 0.2 and vel.z*mobkit.friction or 0}
	end
	
	-- bounciness
	if self.springiness and self.springiness > 0 then
		
		if colinfo and colinfo.collides then
			for _,c in ipairs(colinfo.collisions) do
				if c.old_velocity[c.axis] > 0.1 then
					vnew[c.axis] = vnew[c.axis] * self.springiness * -1
				end
			end	
		elseif not colinfo then					-- MT 5.2 and earlier
			for _,k in ipairs({'y','z','x'}) do			
				if vel[k]==0 and abs(self.lastvelocity[k])> 0.1 then 
					vnew[k]=-self.lastvelocity[k]*self.springiness 
				end
			end
		end
	end
	
	self.object:set_velocity(vnew)
	
	-- buoyancy
	local surface = nil
	local surfnodename = nil
	local spos = mobkit.get_stand_pos(self)
	spos.y = spos.y+0.01
	-- get surface height
	local snodepos = mobkit.get_node_pos(spos)
	local surfnode = mobkit.nodeatpos(spos)
	while surfnode and surfnode.drawtype == 'liquid' do
		surfnodename = surfnode.name
		surface = snodepos.y+0.5
		if surface > spos.y+self.height then break end
		snodepos.y = snodepos.y+1
		surfnode = mobkit.nodeatpos(snodepos)
	end
	self.isinliquid = surfnodename
	if surface then				-- standing in liquid
--		self.isinliquid = true
		local submergence = min(surface-spos.y,self.height)/self.height
--		local balance = self.buoyancy*self.height
		local buoyacc = mobkit.gravity*(self.buoyancy-submergence)
		mobkit.set_acceleration(self.object,
			{x=-vel.x*self.water_drag,y=buoyacc-vel.y*abs(vel.y)*0.4,z=-vel.z*self.water_drag})
	else
--		self.isinliquid = false
		self.object:set_acceleration({x=0,y=mobkit.gravity,z=0})
	end
	
end

function mobkit.vitals(self)
	-- vitals: fall damage
	local vel = self.object:get_velocity()
	local velocity_delta = abs(self.lastvelocity.y - vel.y)
	if velocity_delta > mobkit.safe_velocity then
		self.hp = self.hp - floor(self.max_hp * min(1, velocity_delta/mobkit.terminal_velocity))
	end
	
	-- vitals: oxygen
	if self.lung_capacity then
		local colbox = self.object:get_properties().collisionbox
		local headnode = mobkit.nodeatpos(mobkit.pos_shift(self.object:get_pos(),{y=colbox[5]})) -- node at hitbox top
		if headnode and headnode.drawtype == 'liquid' then 
			self.oxygen = self.oxygen - self.dtime
		else
			self.oxygen = self.lung_capacity
		end
			
		if self.oxygen <= 0 then self.hp=0 end	-- drown
	end
end

function mobkit.statfunc(self)
	local tmptab={}
	tmptab.memory = self.memory
	tmptab.hp = self.hp
	tmptab.texture_no = self.texture_no
	return minetest.serialize(tmptab)
end

function mobkit.actfunc(self, staticdata, dtime_s)

	self.logic = self.logic or self.brainfunc
	self.physics = self.physics or mobkit.physics
	
	self.lqueue = {}
	self.hqueue = {}
	self.nearby_objects = {}
	self.nearby_players = {}
	self.pos_history = {}
	self.path_dir = 1
	self.time_total = 0
	self.water_drag = self.water_drag or 1

	local sdata = minetest.deserialize(staticdata)
	if sdata then 
		for k,v in pairs(sdata) do
			self[k] = v
		end
	end
	
	if self.textures==nil then
		local prop_tex = self.object:get_properties().textures
		if prop_tex then self.textures=prop_tex end
	end
	
	if not self.memory then 		-- this is the initial activation
		self.memory = {} 
		
		-- texture variation
		if #self.textures > 1 then self.texture_no = random(#self.textures) end
	end
	
	if self.timeout and self.timeout>0 and dtime_s > self.timeout and next(self.memory)==nil then
		self.object:remove()
	end
	
	-- apply texture
	if self.textures and self.texture_no then
		local props = {}
		props.textures = {self.textures[self.texture_no]}
		self.object:set_properties(props)
	end

--hp
	self.max_hp = self.max_hp or 10
	self.hp = self.hp or self.max_hp
--armor
	if type(self.armor_groups) ~= 'table' then
		self.armor_groups={}
	end
	self.armor_groups.immortal = 1
	self.object:set_armor_groups(self.armor_groups)
	
	self.buoyancy = self.buoyancy or 0
	self.oxygen = self.oxygen or self.lung_capacity
	self.lastvelocity = {x=0,y=0,z=0}
	self.sensefunc=sensors()
end

function mobkit.stepfunc(self,dtime,colinfo)	-- not intended to be modified
	self.dtime = min(dtime,0.2)
	self.height = mobkit.get_box_height(self)
	
--  physics comes first
	local vel = self.object:get_velocity()
	
	if colinfo then 
		self.isonground = colinfo.touching_ground
	else
		if self.lastvelocity.y==0 and vel.y==0 then
			self.isonground = true
		else
			self.isonground = false
		end
	end
	
	self:physics()

	if self.logic then
		if self.view_range then self:sensefunc() end
		self:logic()
		execute_queues(self)
	end
	
	self.lastvelocity = self.object:get_velocity()
	self.time_total=self.time_total+self.dtime
end

-- load example behaviors
dofile(minetest.get_modpath("mobkit") .. "/example_behaviors.lua")

minetest.register_on_mods_loaded(function()
	local mbkfuns = ''
	for n,f in pairs(mobkit) do
		if type(f) == 'function' then
			mbkfuns = mbkfuns .. n .. string.split(minetest.serialize(f),'.lua')[2] or ''
		end
	end
	local crc = minetest.sha1(mbkfuns)
--  dbg(crc)
	if crc ~= 'a061770008fe9ecf8e1042a227dc3beabd10e481' then
		minetest.log("error","Mobkit namespace inconsistent, has been modified by other mods.")
	end
end)