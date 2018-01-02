--bios
modem = component.proxy(component.list("modem")())

function sleep(n)
	local deadline = computer.uptime() + (n or 0)
	repeat
		computer.pullSignal(deadline - computer.uptime())
	until computer.uptime() >= deadline
end

env = {require = require, drone = component.proxy(component.list("drone")()), addUser = computer.addUser, setArchitecture = computer.setArchitecture, beep = computer.beep, sleep = sleep}

PORT = 5
energy = 5000
clock = os.clock

started = false
code = "while true do beep() sleep(1) end"
GMAddr = ""

modem.open(PORT)

-------------------Thread------------------
computer.SingleThread = computer.pullSignal
local thread = {}
 
local mainThread
local timeouts
 
local function MultiThread( _timeout )
  if coroutine.running()==mainThread then
    local mintime = _timeout or math.huge
    local co=next(timeouts)
    while co do
      if coroutine.status( co ) == "dead" then
        timeouts[co],co=nil,next(timeouts,co)
      else
        if timeouts[co] < mintime then mintime=timeouts[co] end
        co=next(timeouts,co)
      end
    end
    if not next(timeouts) then
      computer.pullSignal=computer.SingleThread
      computer.pushSignal("AllThreadsDead")
    end
    local event={computer.SingleThread(mintime)}
    local ok, param
    for co in pairs(timeouts) do
      ok, param = coroutine.resume( co, table.unpack(event) )
      if not ok then timeouts={} error( param )
      else timeouts[co] = param or math.huge end
    end
    return table.unpack(event)
  else
    return coroutine.yield( _timeout )
  end
end
 
function thread.init()
  mainThread=coroutine.running()
  timeouts={}
end
 
function thread.create(f,...)
  computer.pullSignal=MultiThread
  local co=coroutine.create(f)
  timeouts[co]=math.huge
  local ok, param = coroutine.resume( co, ... )
  if not ok then timeouts={} error( param )
  else timeouts[co] = param or math.huge end
  return co
end
 
function thread.kill(co)
  timeouts[co]=nil
end
 
function thread.killAll()
  timeouts={}
  computer.pullSignal=computer.SingleThread
end
 
function thread.waitForAll()
  repeat
  until MultiThread()=="AllThreadsDead"
end

thread.init()
-------------------------------------------

function sendMsg(str)
	modem.send(GMAddr, PORT, str)
end

function startCode()
	started = true
	assert(load(code, nil, nil, env))()
	started = false
end

function stopCode()
	if codeTH ~= nil then
		started = false
		thread.kill(codeTH)
		codeTH = nil
	else
		sendMsg("rip")
		started = false
	end
end

function energyTick()
	while true do
		if started then
			energy = energy-0.4
			if energy<1 then
				stopCode()
				backToHome()
			end
		end
		sleep(0.05)
	end
end

function backToHome()
	--home
end

function main()
	while true do
		msg = {computer.pullSignal()}

		if msg[6] == "ping" then
			if started then
				sendMsg("pong")
			end
		elseif msg[6] == "code" then
			if load(msg[7]) ~= nil then
				code=msg[7]
			else
				sendMsg("Syntax error")
			end
		elseif msg[6] == "start" then
			if code ~= "" and started == false then
				codeTH = thread.create(startCode)
			else
				sendMsg("Code not found")
			end
		elseif msg[6] == "stop" then
			stopCode()
		elseif msg[6] == "home" then
			backToHome()
		end
		sleep(0.05)
	end
end

thread.create(main)
thread.create(energyTick)
thread.waitForAll()