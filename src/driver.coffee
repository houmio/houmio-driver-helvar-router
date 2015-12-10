net = require('net')
Bacon = require('baconjs')
carrier = require('carrier')
async = require('async')

console.log("KULLI")

routerPortsS = process.env.ROUTER_PORTS
routerPorts = routerPortsS.split(':')

exit = (msg) ->
  console.log msg
  process.exit 1

houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"

bridgeSocket = new net.Socket()

routerSocket = new net.Socket()



toDaliCommand = (command) ->
	bri = if command.data.on then command.data.bri else 0
	return '>V:1,C:13,G:'+command.data.protocolAddress+',L:'+bri+',F:50#'

isWriteMessage = (message) -> message.command is "write"

toLines = (socket) ->
  Bacon.fromBinder (sink) ->
    carrier.carry socket, sink
    socket.on "close", -> sink new Bacon.End()
    socket.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )

openBridgeWriteMessageStream = (socket, protocolName) -> (cb) ->
  socket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], ->
    lineStream = toLines socket
    messageStream = lineStream.map JSON.parse
    messageStream.onEnd -> exit "Bridge stream ended, protocol: #{protocolName}"
    messageStream.onError (err) -> exit "Error from bridge stream, protocol: #{protocolName}, error: #{err}"
    writeMessageStream = messageStream.filter isWriteMessage
    cb null, writeMessageStream

openStreams = [ openBridgeWriteMessageStream(bridgeSocket, "HELVAR-ROUTER")]

async.series openStreams, (err, [daliWriteMessages]) ->
  if err then exit err
  daliWriteMessages
    .map toDaliCommand
    .onValue (d) -> routerSocket.write JSON.stringify d

	bridgeSocket.write (JSON.stringify { command: "driverReady", protocol: "helvar-router"}) + "\n"


routerSocket.connect routerPorts[0], '127.0.0.1', ->
	routerSocket.on "error", (err) -> exit(err)
	routerSocket.on "close", -> exit("Socket closed")
	#routerSocket.on "data", (data) -> console.log data

