
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

function mobkit.statfunc(self)
	local tmptab={}
	tmptab.memory = self.memory
	tmptab.hp = self.hp
	tmptab.texture_no = self.texture_no
	return minetest.serialize(tmptab)
end

function mobkit.actfunc(self, staticdata, dtime_s)
	self.lqueue = {}
	self.hqueue = {}
	self.nearby_objects = {}
	self.nearby_players = {}
	self.pos_history = {}
	self.path_dir = 1
	self.time_total = 0

	local sdata = minetest.deserialize(staticdata)
	if sdata then 
		for k,v in pairs(sdata) do
			self[k] = v
		end
	end
	
	if self.timeout and self.timeout>0 and dtime_s > self.timeout and next(self.memory)==nil then
		self.object:remove()
	end
	
	if not self.memory then 		-- this is the initial activation
		self.memory = {} 
		
		-- texture variation
		if #self.textures > 1 then self.texture_no = random(#self.textures) end
	end
	
	-- apply texture
	if self.texture_no then
		local props = {}
		props.textures = {self.textures[self.texture_no]}
		self.object:set_properties(props)
	end

--hp
	self.hp = self.hp or (self.max_hp or 10)
--armor
	if type(self.armor_groups) ~= 'table' then
		self.armor_groups={}
	end
	self.armor_groups.immortal = 1
	self.object:set_armor_groups(self.armor_groups)
	
	self.oxygen = self.oxygen or self.lung_capacity
	self.lastvelocity = {x=0,y=0,z=0}
	self.height = self.collisionbox[5] - self.collisionbox[2]
	self.sensefunc=sensors()
end

function mobkit.stepfunc(self,dtime)	-- not intended to be modified
	self.dtime = dtime
--  physics comes first
--	self.object:set_acceleration({x=0,y=mobkit.gravity,z=0})
	local vel = self.object:get_velocity()
	
--	if self.lastvelocity.y == vel.y then
	if abs(self.lastvelocity.y-vel.y)<0.001 then
		self.isonground = true
	else
		self.isonground = false
	end
	
	-- dumb friction
	if self.isonground then
		self.object:set_velocity({x= vel.x> 0.2 and vel.x*mobkit.friction or 0,
								y=vel.y,
								z=vel.z > 0.2 and vel.z*mobkit.friction or 0})
	end
	
-- bounciness
	if self.springiness and self.springiness > 0 then
		local vnew = vector.new(vel)
		
		if not self.collided then						-- ugly workaround for inconsistent collisions
			for _,k in ipairs({'y','z','x'}) do			
				if vel[k]==0 and abs(self.lastvelocity[k])> 0.1 then 
					vnew[k]=-self.lastvelocity[k]*self.springiness 
				end
			end
		end
		
		if not vector.equals(vel,vnew) then
			self.collided = true
		else
			if self.collided then
				vnew = vector.new(self.lastvelocity)
			end
			self.collided = false
		end
		
		self.object:set_velocity(vnew)
	end
	
	-- buoyancy
	local spos = mobkit.get_stand_pos(self)
	spos.y = spos.y+0.01
	-- get surface height
--	local surface = mobkit.get_node_pos(spos).y+0.5
	local surface = nil
	local snodepos = mobkit.get_node_pos(spos)
	local surfnode = mobkit.nodeatpos(spos)
	while surfnode and surfnode.drawtype == 'liquid' do
		surface = snodepos.y+0.5
		if surface > spos.y+self.height then break end
		snodepos.y = snodepos.y+1
		surfnode = mobkit.nodeatpos(snodepos)
	end
	if surface then				-- standing in liquid
		self.isinliquid = true
		local submergence = min(surface-spos.y,self.height)
		local balance = self.buoyancy*self.height
		local buoyacc = mobkit.gravity*((balance - submergence)^2/balance^2*sign(balance - submergence))
		self.object:set_acceleration({x=-vel.x,y=buoyacc-vel.y*abs(vel.y)*0.7,z=-vel.z})
	else
		self.isinliquid = false
		self.object:set_acceleration({x=0,y=mobkit.gravity,z=0})
	end
	
	
	
	-- local footnode = mobkit.nodeatpos(spos)
	-- local headnode
	-- if footnode and footnode.drawtype == 'liquid' then
		
		-- vel = self.object:get_velocity()
		-- headnode = mobkit.nodeatpos(mobkit.pos_shift(spos,{y=self.height or 0}))	-- TODO: height may be nil
		-- local submergence = headnode.drawtype=='liquid' 
			-- and	self.buoyancy-1
			-- or (self.buoyancy*self.height-(1-(spos.y+0.5)%1))^2/(self.buoyancy*self.height)^2*sign(self.buoyancy*self.height-(1-(spos.y+0.5)%1))

		-- local buoyacc = submergence * mobkit.gravity
		-- self.object:set_acceleration({x=-vel.x,y=buoyacc-vel.y*abs(vel.y)*0.5,z=-vel.z})

	-- end

	if self.brainfunc then
		-- vitals: fall damage
		vel = self.object:get_velocity()
		local velocity_delta = abs(self.lastvelocity.y - vel.y)
		if velocity_delta > mobkit.safe_velocity then
			self.hp = self.hp - floor((self.max_hp-100) * min(1, velocity_delta/mobkit.terminal_velocity))
		end
		
		-- vitals: oxygen
		local headnode = mobkit.nodeatpos(mobkit.pos_shift(self.object:get_pos(),{y=self.collisionbox[5]})) -- node at hitbox top
		if headnode and headnode.drawtype == 'liquid' then 
			self.oxygen = self.oxygen - self.dtime
		else
			self.oxygen = self.lung_capacity
		end
			
		if self.oxygen <= 0 then self.hp=0 end	-- drown

		
		self:sensefunc()
		self:brainfunc()
		execute_queues(self)
	end
	
	self.lastvelocity = self.object:get_velocity()
	self.time_total=self.time_total+self.dtime
end