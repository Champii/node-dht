require! {
  net
  events : EventEmitter
  \./Debug
  \./Hash
}

net.Socket.prototype._orig_connect = net.Socket.prototype.connect

net.Socket.prototype.connect = ->
  if typeof @conn_timeout isnt 'undefined' && @conn_timeout > 0
    @addListener 'connect', ~>
      # console.log 'OnConnect'
      clearTimeout @conn_timer

    @conn_timer = setTimeout ~>
      # console.log 'Timeout'
      @emit 'connect_timeout'
      # @destroy!
    , @conn_timeout

  # console.log 'Trying to connect'
  @_orig_connect.apply @, arguments

net.Socket.prototype.setConnTimeout = (timeout) ->
  @conn_timeout = parseInt timeout, 10

class Node extends EventEmitter

  # stats
  @inRequests = 0
  @outRequests = 0

  (@host, @port, @hash, @self, @client) ->
    @debug = new Debug "DHT::Node::#{@hash?Value! || '(not connected)'}", Debug.colors.cyan

    if is-type \String @port
      @port = +@port

    @nonce = 0
    @ready = false
    @destroyed = false
    @lastSeen = new Date
    @firstSeen = new Date
    @connecting = false
    @waitingAnswers = {}

    @self.routing.StoreNode @

    if @client?
      @debug.Warn "? Already existing client !!"
      @ready = true
      # console.log 'CLIENT EXISTS'
      @SetListener!
    # console.log 'New Node', @hash

    @protocole =
      PING:       @~Pong
      STORE:      @~Stored
      FIND_NODE:  @~FoundNode
      FIND_VALUE: @~FoundValue

    @debug.Log "= New node instantiated " + if @host and @port then "#{@host}:#{@port}" else ""

    @ping_timer = setInterval @~Ping, @self.config.pingInterval * 1000
    # console.log 'NEW NODE' @host, @port

    # @Connect!


  SetListener: (done = (->)) ->
    tmpData = ''

    @client.on \data ~>
      data = tmpData + it.toString!
      tmpData := ''

      if not data.includes '\0'
        tmpData := data
        return
      else if data[*-1] isnt '\0'
        data = compact data.split '\0'
        tmpData := data.pop!
        data = data.join '\0'

      # console.log tmpData

      arr = data
        |> split '\0'
        |> compact
        |> map JSON.parse
        |> each @~HandleReceive

    @client.once \error ~>
      @debug.Error 'X ' + it

      @Disconnect!
      done 'Error' + it
      done := ->

    @client.once \timeout ~>
      @debug.Error "X Request timeout"

      @Disconnect!
      done 'timeout'
      done := ->

    @client.once \connect_timeout ~>
      @debug.Error "X Connection timeout"

      @Disconnect!
      done 'timeoutConnect'
      done := ->

  HandleReceive: ->
    Node.inRequests++
    @ResetTimer!

    if not @hash?
      @ <<< it.sender{ip, port, hash}
      @hash = new Hash @hash.value.data
      @debug = new Debug "DHT::Node::#{@hash.Value!}", Debug.colors.cyan
      @self.routing.StoreNode @

    if it.answerTo?
      if not @waitingAnswers[it.answerTo]?
        @debug.Error "X Unknown message to answer to"
        return

      answerTo = @waitingAnswers[it.answerTo]

      if answerTo.answered
        return console.error 'ALREADY ANSWERED ????' answerTo

      if answerTo.msgHash isnt it.answerTo
        delete @waitingAnswers[it.answerTo]
        @debug.Error "X Bad answer"
        return

      @lastSeen = new Date
      clearTimeout answerTo.timer

      answerTo.done null, it
      answerTo.answered = true
    else
      if @protocole[it.msg]?
        that it
      else
        @self.emit \unknownMsg, it


  ResetTimer: ->
    clearInterval @ping_timer
    @ping_timer = setInterval @~Ping, @self.config.pingInterval * 1000

  Connect: (done = ->) ->
    if @connecting or @ready
      @debug.Warn "? Already connected: #{@hash.Value!}"
      return done!

    @connecting = true

    @client = new net.Socket
    @client.setConnTimeout @self.config.connectTimeout * 1000

    # @client.setTimeout 600000ms #10mn
    # @client.setTimeout 6000ms #6sec

    @SetListener (a, b) -> done a, b
    @debug.Log "> Connecting to #{@host}:#{@port}..."
    @client.connect @{host, port}, ~>
      @debug.Log "< Connected to #{@host}:#{@port}..."
      @ready = true
      @connecting = false
      done!
      done := ->

  ###
  # Requests
  ###

  Ping: (done = ->) ->
    @debug.Log "> Ping"
    @_SendMessage msg: \PING, (err, res) ~>
      return done err if err?

      @debug.Log "< Pong"
      done null, res

  FindNode: (hash, done = ->) ->
    @debug.Log "> Find node: #{hash.Value!}"
    @_SendMessage msg: \FIND_NODE value: hash.value, (err, res) ~>
      return done err if err?

      @debug.Log "< Found node: #{res?value?length}"
      done null, res?value

  FindValue: (hash, done = ->) ->
    @debug.Log "> Find value: #{hash.Value!}"
    @_SendMessage msg: \FIND_VALUE value: hash.value, (err, res) ~>
      return done err if err?

      @debug.Log "< Found value: #{res?value?length}"
      done null, res.value

  Store: (key, value, done = ->) ->
    @debug.Log "> Store: #{key.Value!} -> #{value}"
    @_SendMessage msg: \STORE value: {value, key}, (err, res) ~>
      return done err if err?

      @debug.Log "< Stored: #{key.Value!} -> #{value}"
      done null, res.value

  ###
  # Answers
  ###

  Pong: ->
    @debug.Log "< Ping"
    @_SendMessage msg: \PONG answerTo: it.msgHash
    @debug.Log "> Pong"

  FoundNode: ->
    hash = Hash.Deserialize it
    @debug.Log "< Find node: #{hash.Value!}"
    value = map (.Serialize!), @self.routing.FindNode hash
    @_SendMessage msg: \FOUND_NODE answerTo: it.msgHash, value: value
    @debug.Log "> Found nodes: #{value.length}"

  Stored: ->
    hash = Hash.Deserialize it.value.key
    @debug.Log "< Store: #{hash.Value!}"
    @_SendMessage msg: \STORED answerTo: it.msgHash, value: @self.StoreLocal it
    @debug.Log "> Stored"

  FoundValue: ->
    @debug.Log "< Find value: #{it.key}"
    [value, bucket] = @self.FindValueLocal it

    if value?
      @debug.Log "> Found value: #{it.key}"
      @_SendMessage msg: \FOUND_VALUE answerTo: it.msgHash, value: key: it.value, value: value
    else if bucket?
      @debug.Log "> Found value: forward -> #{bucket.length} nodes"
      @_SendMessage msg: \FOUND_NODE answerTo: it.msgHash, value: map (.Serialize!), bucket

  _SendMessage: (obj, done = (->)) ->
    if not @ready
      @debug.Warn "Not ready: #{@host}:#{@port}"
      return done 'not ready'

    Node.outRequests++

    obj.nonce = @nonce++
    obj.timestamp = new Date().getTime!
    obj.sender = @self{hash, port} <<< ip: \localhost
    obj.msgHash = Hash.Create(JSON.stringify obj).Value!

    @client.write (JSON.stringify obj) + '\0'

    obj.done = done

    if @nonce > 10000
      @nonce = 0

    # obj.timer = setTimeout ~>
    #   console.log 'TIMEOUT request' obj
    #   @Disconnect!
    # , 10000

    @waitingAnswers[obj.msgHash] = obj

  Disconnect: ->
    clearInterval @ping_timer
    @client.destroy! if not @client?.destroyed
    @emit 'disconnected'
    @ready = false

  Serialize: ->
    @{hash, ip, port}

  @Deserialize = (info, self, client) ->
    if not info?
      new @ null, null, null, self, client
    else
      hash = (new Hash info.hash.value.data)

      if hash.Value! is self.hash.Value!
        return null

      found = self.routing.FindOneNode hash
      if found
        that
      else
        new @ info.ip, info.port, hash, self, client

module.exports = Node
