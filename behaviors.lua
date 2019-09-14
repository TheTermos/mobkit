-- node by node land movement macros
function mobkit.get_next_waypoint(self,tpos)
	local pos = mobkit.get_stand_pos(self)
	local dir=vector.direction(pos,tpos)
	local neighbor = mobkit.dir2neighbor(dir)
	local function update_pos_history(self,pos)
		table.insert(self.pos_history,1,pos)
		if #self.pos_history > 2 then table.remove(self.pos_history,#self.pos_history) end
	end
	local nogopos = self.pos_history[2]
	
	local height, pos2, liquidflag = mobkit.is_neighbor_node_reachable(self,neighbor)
--minetest.chat_send_all('pos2 ' .. minetest.serialize(pos2))
--minetest.chat_send_all('nogopos ' .. minetest.serialize(nogopos))	
	if height and not liquidflag 
	and not (nogopos and mobkit.isnear2d(pos2,nogopos,0.1)) then

		local heightl = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,-1))
		if heightl and abs(heightl-height)<0.001 then
			local heightr = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,1))
			if heightr and abs(heightr-height)<0.001 then
				dir.y = 0
				local dirn = vector.normalize(dir)
				local npos = mobkit.get_node_pos(mobkit.pos_shift(pos,neighbors[neighbor]))
				local factor = abs(dirn.x) > abs(dirn.z) and abs(npos.x-pos.x) or abs(npos.z-pos.z)
				pos2=mobkit.pos_shift(pos,{x=dirn.x*factor,z=dirn.z*factor})
			end
		end
		update_pos_history(self,pos2)
		return height, pos2
	else

		for i=1,3 do
			-- scan left
			local height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,-i*self.path_dir))
			if height and not liq 
			and not (nogopos and mobkit.isnear2d(pos2,nogopos,0.1)) then
				update_pos_history(self,pos2)
				return height,pos2 
			end			
			-- scan right
			height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,i*self.path_dir))
			if height and not liq 
			and not (nogopos and mobkit.isnear2d(pos2,nogopos,0.1)) then
				update_pos_history(self,pos2)
				return height,pos2 
			end
		end
		--scan rear
		height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,4))
		if height and not liq 
		and not (nogopos and mobkit.isnear2d(pos2,nogopos,0.1)) then
			update_pos_history(self,pos2)
			return height,pos2 
		end
	end
	-- stuck condition here
	table.remove(self.pos_history,2)
	self.path_dir = self.path_dir*-1	-- subtle change in pathfinding
end

function mobkit.get_next_waypoint_fast(self,tpos,nogopos)
	local pos = mobkit.get_stand_pos(self)
	local dir=vector.direction(pos,tpos)
	local neighbor = mobkit.dir2neighbor(dir)
	local height, pos2, liquidflag = mobkit.is_neighbor_node_reachable(self,neighbor)
	
	if height and not liquidflag then
		local fast = false
		heightl = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,-1))
		if heightl and abs(heightl-height)<0.001 then
			heightr = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,1))
			if heightr and abs(heightr-height)<0.001 then
				fast = true
				dir.y = 0
				local dirn = vector.normalize(dir)
				local npos = mobkit.get_node_pos(mobkit.pos_shift(pos,neighbors[neighbor]))
				local factor = abs(dirn.x) > abs(dirn.z) and abs(npos.x-pos.x) or abs(npos.z-pos.z)
				pos2=mobkit.pos_shift(pos,{x=dirn.x*factor,z=dirn.z*factor})
			end
		end
		return height, pos2, fast
	else

		for i=1,4 do
			-- scan left
			height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,-i))
			if height and not liq then return height,pos2 end
			-- scan right
			height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,i))
			if height and not liq then return height,pos2 end
		end
	end
end

function mobkit.goto_next_waypoint(self,tpos)
	local height, pos2 = mobkit.get_next_waypoint(self,tpos)
	
	if not height then return false end
	
	if height <= 0.01 then
		local yaw = self.object:get_yaw()
		local tyaw = minetest.dir_to_yaw(vector.direction(self.object:get_pos(),pos2))
		if abs(tyaw-yaw) > 1 then
			mobkit.lq_turn2pos(self,pos2) 
		end
		mobkit.lq_dumbwalk(self,pos2)
	else
		mobkit.lq_turn2pos(self,pos2) 
		mobkit.lq_dumbjump(self,height) 
	end
	return true
end

function mobkit.dumbstep(self,height,tpos,speed_factor)
	if height <= 0.001 then
		mobkit.lq_turn2pos(self,tpos) 
		mobkit.lq_dumbwalk(self,tpos,speed_factor)
	else
		mobkit.lq_turn2pos(self,tpos) 
		mobkit.lq_dumbjump(self,height) 
	end
	mobkit.lq_idle(self,random(1,6))
end

----------------------------
-- LOW LEVEL QUEUE FUNCTIONS
----------------------------

function mobkit.lq_turn2pos(self,tpos)
	local func=function(self)
		local pos = self.object:get_pos()
		return mobkit.turn2yaw(self,
			minetest.dir_to_yaw(vector.direction(pos,tpos)))
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_idle(self,duration,anim)
	anim = anim or 'stand'
	local init = true
	local func=function(self)
		if init then 
			mobkit.animate(self,anim) 
			init=false
		end
		duration = duration-self.dtime
		if duration <= 0 then return true end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_dumbwalk(self,dest,speed_factor)
	local timer = 3			-- failsafe
	speed_factor = speed_factor or 1
	local func=function(self)
		mobkit.animate(self,'walk')
		timer = timer - self.dtime
		if timer < 0 then return true end
		
		local pos = mobkit.get_stand_pos(self)
		local y = self.object:get_velocity().y

		if mobkit.is_there_yet2d(pos,minetest.yaw_to_dir(self.object:get_yaw()),dest) then
--		if mobkit.isnear2d(pos,dest,0.25) then
			if not self.isonground or abs(dest.y-pos.y) > 0.1 then		-- prevent uncontrolled fall when velocity too high
--			if abs(dest.y-pos.y) > 0.1 then	-- isonground too slow for speeds > 4
				self.object:set_velocity({x=0,y=y,z=0})
			end
			return true 
		end

		if self.isonground then
			local dir = vector.normalize(vector.direction({x=pos.x,y=0,z=pos.z},
														{x=dest.x,y=0,z=dest.z}))
			dir = vector.multiply(dir,self.max_speed*speed_factor)
--			self.object:set_yaw(minetest.dir_to_yaw(dir))
			mobkit.turn2yaw(self,minetest.dir_to_yaw(dir))
			dir.y = y
			self.object:set_velocity(dir)
		end
	end
	mobkit.queue_low(self,func)
end

-- initial velocity for jump height h, v= a*sqrt(h*2/a) ,add 20%
function mobkit.lq_dumbjump(self,height,anim)
	anim = anim or 'stand'
	local jump = true
	local func=function(self)
	local yaw = self.object:get_yaw()
		if self.isonground then
			if jump then
				mobkit.animate(self,anim)
				local dir = minetest.yaw_to_dir(yaw)
				dir.y = -mobkit.gravity*sqrt((height+0.35)*2/-mobkit.gravity)
				self.object:set_velocity(dir)
				jump = false
			else				-- the eagle has landed
				return true
			end
		else	
			local dir = minetest.yaw_to_dir(yaw)
			local vel = self.object:get_velocity()
			if self.lastvelocity.y < 0.9 then
				dir = vector.multiply(dir,3)
			end
			dir.y = vel.y
			self.object:set_velocity(dir,yaw)
		end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_jumpout(self)
	local phase = 1
	local func=function(self)
		local vel=self.object:get_velocity()
		if phase == 1 then
			vel.y=vel.y+5
			self.object:set_velocity(vel)
			phase = 2
		else
			if vel.y < 0 then return true end
			local dir = minetest.yaw_to_dir(self.object:get_yaw())
			dir.y=vel.y
			self.object:set_velocity(dir)
		end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_freejump(self)
	local phase = 1
	local func=function(self)
		local vel=self.object:get_velocity()
		if phase == 1 then
			vel.y=vel.y+6
			self.object:set_velocity(vel)
			phase = 2
		else
			if vel.y <= 0.01 then return true end
			local dir = minetest.yaw_to_dir(self.object:get_yaw())
			dir.y=vel.y
			self.object:set_velocity(dir)
		end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_jumpattack(self,height,target)
	local phase=1		
	local func=function(self)
		if not mobkit.is_alive(target) then return true end
		if self.isonground then
			if phase==1 then	-- collision bug workaround
				local vel = self.object:get_velocity()
				vel.y = -mobkit.gravity*sqrt(height*2/-mobkit.gravity)
				self.object:set_velocity(vel)
				mobkit.make_sound(self,'charge')
				phase=2
			else
				return true
			end
		elseif phase==2 then
			local dir = minetest.yaw_to_dir(self.object:get_yaw())
			local vy = self.object:get_velocity().y
			dir=vector.multiply(dir,6)
			dir.y=vy
			self.object:set_velocity(dir)
			phase=3
		elseif phase==3 then	-- in air
			local twidth = target:get_properties().collisionbox[1]
			local pos = self.object:get_pos()
			-- calculate attack spot
			local dir = minetest.yaw_to_dir(self.object:get_yaw())
			dir2 = vector.add(dir,self.attack.range+twidth)
			local apos = vector.add(pos,dir2)
--			local tpos = mobkit.get_stand_pos(target) 						--test
--			tpos.y = tpos.y+height
			if mobkit.isnear2d(apos,target:get_pos(),0.25) then	--bite
				target:punch(self.object,1,self.attack)
					-- bounce off
				local vy = self.object:get_velocity().y
				self.object:set_velocity({x=dir.x*-3,y=vy,z=dir.z*-3})	
					-- play attack sound if defined
				mobkit.make_sound(self,'attack')
				phase=4
			end
		end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_fallover(self)
	local zrot = 0
	local init = true
	local func=function(self)
		if init then
			local vel = self.object:get_velocity()
			self.object:set_velocity(mobkit.pos_shift(vel,{y=1}))
			mobkit.animate(self,'stand')
			init = false
		end
		zrot=zrot+pi*0.05
		local rot = self.object:get_rotation()
		self.object:set_rotation({x=rot.x,y=rot.y,z=zrot})
		if zrot >= pi*0.5 then return true end
	end
	mobkit.queue_low(self,func)
end
-----------------------------
-- HIGH LEVEL QUEUE FUNCTIONS
-----------------------------

function mobkit.hq_roam(self,prty)
	local func=function(self)
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local neighbor = random(8)

			local height, tpos, liquidflag = mobkit.is_neighbor_node_reachable(self,neighbor)
			if height and not liquidflag then mobkit.dumbstep(self,height,tpos,0.3) end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_follow0(self,tgtobj)	-- probably delete this one
	local func = function(self)
		if not tgtobj then return true end
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local opos = tgtobj:get_pos()
			if vector.distance(pos,opos) > 3 then
				local neighbor = mobkit.dir2neighbor(vector.direction(pos,opos))
if not neighbor then return true end		--temp debug
				local height, tpos = mobkit.is_neighbor_node_reachable(self,neighbor)
				if height then mobkit.dumbstep(self,height,tpos)
				else	
					for i=1,4 do --scan left
						height, tpos = mobkit.is_neighbor_node_reachable(self,(8+neighbor-i-1)%8+1)
						if height then mobkit.dumbstep(self,height,tpos)
							break
						end		--scan right
						height, tpos = mobkit.is_neighbor_node_reachable(self,(neighbor+i-1)%8+1)
						if height then mobkit.dumbstep(self,height,tpos)
							break
						end
					end
				end
			else
				mobkit.lq_idle(self,1)
			end
		end
	end
	mobkit.queue_high(self,func,0)
end

function mobkit.hq_follow(self,prty,tgtobj)
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local opos = tgtobj:get_pos()
			if vector.distance(pos,opos) > 3 then
				mobkit.goto_next_waypoint(self,opos)
			else
				mobkit.lq_idle(self,1)
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_goto(self,prty,tpos)
	local func = function(self)
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			if vector.distance(pos,tpos) > 3 then
				mobkit.goto_next_waypoint(self,tpos)
			else
				return true
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_runfrom(self,prty,tgtobj)
	local init=true
	local timer=6
	local func = function(self)
	
		if not mobkit.is_alive(tgtobj) then return true end
		if init then
			timer = timer-self.dtime
			if timer <=0 or vector.distance(self.object:get_pos(),tgtobj:get_pos()) < 8 then
				mobkit.make_sound(self,'scared')
				init=false
			end
			return
		end
		
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local opos = tgtobj:get_pos()
			if vector.distance(pos,opos) < self.view_range*1.1 then
				local tpos = {x=2*pos.x - opos.x,
								y=opos.y,
								z=2*pos.z - opos.z}
				mobkit.goto_next_waypoint(self,tpos)
			else
				self.object:set_velocity({x=0,y=0,z=0})
				return true
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_hunt(self,prty,tgtobj)
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local opos = tgtobj:get_pos()
			local dist = vector.distance(pos,opos)
			if dist > self.view_range then
				return true
			elseif dist > 3 then
				mobkit.goto_next_waypoint(self,opos)
			else
				mobkit.hq_attack(self,prty+1,tgtobj)					
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_warn(self,prty,tgtobj)
	timer=0
	tgttime = 0
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		local pos = mobkit.get_stand_pos(self)
		local opos = tgtobj:get_pos()
		local dist = vector.distance(pos,opos)
		
		if dist > 11 then
			return true
		elseif dist < 4 or timer > 12 then						-- too close man
--			mobkit.clear_queue_high(self)
			mobkit.remember(self,'hate',tgtobj:get_player_name())
			mobkit.hq_hunt(self,prty+1,tgtobj)							-- priority
		else
			timer = timer+self.dtime
			if mobkit.is_queue_empty_low(self) then				
				mobkit.lq_turn2pos(self,opos)
			end
			-- make noise in random intervals
			if timer > tgttime then
				mobkit.make_sound(self,'warn')
				-- if self.sounds and self.sounds.warn then
					-- minetest.sound_play(self.sounds.warn, {object=self.object})
				-- end
				tgttime = timer + 1.1 + random()*1.5
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_die(self)
	local timer = 5
	local start = true
	local func = function(self)
		if start then 
			mobkit.lq_fallover(self) 
			self.brainfunc = function(self) end	-- brain dead as well
			start=false
		end
		timer = timer-self.dtime
		if timer < 0 then self.object:remove() end
	end
	mobkit.queue_high(self,func,100)
end

function mobkit.hq_attack(self,prty,tgtobj)
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		if mobkit.is_queue_empty_low(self) then
			local pos = mobkit.get_stand_pos(self)
--			local tpos = tgtobj:get_pos()
			local tpos = mobkit.get_stand_pos(tgtobj)
			local dist = vector.distance(pos,tpos)
			if dist > 3 then 
				return true
			else
				mobkit.lq_turn2pos(self,tpos)
				local height = tgtobj:is_player() and 0.8 or tgtobj:get_luaentity().height*0.6
				if tpos.y+height>pos.y then 
					mobkit.lq_jumpattack(self,tpos.y+height-pos.y,tgtobj) 
				else
					mobkit.lq_dumbwalk(self,mobkit.pos_shift(tpos,{x=random()-0.5,z=random()-0.5}))
				end
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_liquid_recovery(self,prty)	-- scan for nearest land
	local radius = 1
	local yaw = 0
	local func = function(self)
		if not self.isinliquid then return true end
		local pos=self.object:get_pos()
		local vec = minetest.yaw_to_dir(yaw)
		local pos2 = mobkit.pos_shift(pos,vector.multiply(vec,radius))
		local height, liquidflag = mobkit.get_terrain_height(pos2)
		if height and not liquidflag then
			mobkit.hq_swimto(self,prty,pos2)
			return true
		end
		yaw=yaw+pi*0.25
		if yaw>2*pi then
			yaw = 0
			radius=radius+1
			if radius > self.view_range then	
				self.hp = 0
				return true
			end	
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_swimto(self,prty,tpos)
	local func = function(self)
--		if not self.isinliquid and mobkit.is_queue_empty_low(self) then return true end
		if not self.isinliquid and self.isonground then return true end
--		local pos = self.object:get_pos()
		local pos = mobkit.get_stand_pos(self)
		local y=self.object:get_velocity().y
		local pos2d = {x=pos.x,y=0,z=pos.z}
		local dir=vector.normalize(vector.direction(pos2d,tpos))
		local yaw = minetest.dir_to_yaw(dir)
		
		if mobkit.timer(self,1) then
--perpendicular vectors: {-z,x};{z,-x}
			local offset=self.collisionbox[1]
			local pos1 = mobkit.pos_shift(mobkit.pos_shift(pos,{x=-dir.z*offset,z=dir.x*offset}),dir)
			local h,l = mobkit.get_terrain_height(pos1)
			if h and h>pos.y then
				mobkit.lq_freejump(self)
			else 
				local pos2 = mobkit.pos_shift(mobkit.pos_shift(pos,{x=dir.z*offset,z=-dir.x*offset}),dir)
				local h,l = mobkit.get_terrain_height(pos2)
				if h and h>pos.y then
					mobkit.lq_freejump(self)
				end
			end
		elseif mobkit.turn2yaw(self,yaw) then
			dir.y = y
			self.object:set_velocity(dir)
		end
	end
	mobkit.queue_high(self,func,prty)
end
