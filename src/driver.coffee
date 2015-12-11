net = require('net')
Bacon = require('baconjs')
carrier = require('carrier')
async = require('async')
R = require('ramda')

routerIpsS = process.env.ROUTER_IP_ADDRESSES
routerIps = routerIpsS.split(',')

helvarRouterPort = 50000

exit = (msg) ->
  console.log msg
  process.exit 1

houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"

bridgeSocket = new net.Socket()

routerSocket = new net.Socket()


parseUniverseAddress = (command) ->
	command.data.universeAddress = command.data.protocolAddress.split('/')[0]
	command.data.protocolAddress = command.data.protocolAddress.split('/')[1]
	command

toDaliCommand = (command) ->
	bri = if command.data.on then command.data.bri else 0
	{
		universeAddress: parseInt(command.data.universeAddress),
		#commandStr: '>V:1,C:14,L:'+bri+',F:50,@'+command.data.protocolAddress+'#'
		commandStr: '>V:1,C:13,G:'+command.data.protocolAddress+',L:'+bri+',F:75#'
	}

isWriteMessage = (message) -> message.command is "write"

toLines = (socket) ->
  Bacon.fromBinder (sink) ->
    carrier.carry socket, sink
    socket.on "close", -> sink new Bacon.End()
    socket.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )

openBridgeWriteMessageStream = (socket, protocolName, cb) ->
  socket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], ->
    lineStream = toLines socket
    messageStream = lineStream.map JSON.parse
    messageStream.onEnd -> exit "Bridge stream ended, protocol: #{protocolName}"
    messageStream.onError (err) -> exit "Error from bridge stream, protocol: #{protocolName}, error: #{err}"
    writeMessageStream = messageStream.filter isWriteMessage
    cb writeMessageStream

runDriver = (routerSockets) ->
	openBridgeWriteMessageStream bridgeSocket, "HELVAR-ROUTER", (daliWriteMessages) ->
		daliWriteMessages
			.map parseUniverseAddress
    	.map toDaliCommand
    	.onValue (d) -> routerSockets[d.universeAddress].write d.commandStr
		bridgeSocket.write (JSON.stringify { command: "driverReady", protocol: "helvar-router"}) + "\n"

createSocket = (ip, cb) ->
	socket = new net.Socket()
	socket.connect helvarRouterPort, ip, ->
		console.log("Connected to a router at #{ip}")
		socket.on "error", (err) -> exit(err)
		socket.on "close", -> exit("Socket closed")
		setInterval(->
			#Write to dummy address to keep socket alive
			socket.write('>V:1,C:14,L:0,F:9000,@65#')
		, 1000)
		cb(null,socket)

routerSockets = async.mapSeries routerIps, createSocket, (err, routerSockets) ->
	runDriver routerSockets
	if err then exit("Router connection error")



