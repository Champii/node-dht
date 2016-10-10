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

  (@ip, @port, @hash, @self, @client) ->
    @debug = new Debug "DHT::Node::#{@hash?Value! || '(not connected)'}", Debug.colors.cyan

    if is-type \String @port
      @port = +@port

    @ready = false
    @destroyed = false
    @lastSeen = new Date
    @firstSeen = new Date
    @connecting = false
    @waitingAnswers = {}

    @self.routing.StoreNode @

    if @client
      @debug.Error "X Already existing client !!"
      @ready = true
      # console.log 'CLIENT EXISTS'
      @SetListener!
    # console.log 'New Node', @hash

    @protocole =
      PING:       @~Pong
      STORE:      @~Stored
      FIND_NODE:  @~FoundNode
      FIND_VALUE: @~FoundValue

    @debug.Log "= New node instantiated " + if @ip and @port then "#{@ip}:#{@port}" else ""

    # @ping_timer = setInterval @~Ping, 1000
    # console.log 'NEW NODE' @ip, @port

    # @Connect!


  SetListener: ->
    @client.on \data ~>
      it = JSON.parse it.toString!

      if not @hash?
        # console.log 'not hash' it
        @ <<< it.sender{ip, port, hash}
        @hash = new Hash @hash.value.data
        @debug = new Debug "DHT::Node::#{@hash.Value!}", Debug.colors.cyan
        @self.routing.StoreNode @

      if it.answerTo?
        if not @waitingAnswers[it.answerTo]?
          @debug.Error "X Unknown message to answer to"
          return

        answerTo = @waitingAnswers[it.answerTo]

        if answerTo.msgHash isnt it.answerTo
          delete @waitingAnswers[it.answerTo]
          @debug.Error "X Bad answer"
          return

        @lastSeen = new Date
      #   clearTimeout answerTo.timer

        answerTo.done null, it
      else
        if @protocole[it.msg]?
          that it
        else
          @self.emit \unknownMsg, it

  Connect: (done = ->) ->
    if @connecting or @ready
      @debug.Warn "? Already connected: #{@hash.Value!}"
      return done!

    @connecting = true
    # console.log 'Connect' @ip, @port
    @client = new net.Socket
    @client.setConnTimeout 1000ms
    # console.log 'CreateConnection' @{ip, port}
    # @client = net.createConnection @{ip, port}, ~>
    #   console.log 'Conneccted'

    # @client.setTimeout 600000ms #10mn
    # @client.setTimeout 10000ms #10sec

    @client.once \error ~>
      # console.log 'ERROR' it
      @debug.Error it
      # if @client.destroyed
      #   return
      #
      @Disconnect!
      done 'Error'
      done := ->

    @client.once \timeout ~>
      @debug.Error "X Request timeout"
      # if @client.destroyed
      #   return
      #
      @Disconnect!
      done 'timeout'
      done := ->

    @client.once \connect_timeout ~>
      @debug.Error "X Connection timeout"
      # if @client.destroyed
      #   return

      @Disconnect!
      done 'timeoutConnect'
      done := ->

    @debug.Log "> Connecting to #{@ip}:#{@port}..."
    @client.connect @{ip, port}, ~>
      @debug.Log "< Connected to #{@ip}:#{@port}..."
      @ready = true
      @connecting = false
      @SetListener!
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

      # console.log 'WHAT', err, res

      @debug.Log "< Found node: #{res?value?length}"
      done null, res?value

  FindValue: (hash, done = ->) ->
    @debug.Log "> Find value: #{hash.Value!}"
    @_SendMessage msg: \FIND_VALUE value: hash.value, (err, res) ~>
      return done err if err?

      # console.log 'FOUND' res
      @debug.Log "< Found value: #{res?value?length}"
      done null, res.value

  Store: (key, value, done = ->) ->
    @debug.Log "> Store: #{key} -> #{value}"
    @_SendMessage msg: \STORE value: {value, key}, (err, res) ~>
      return done err if err?

      @debug.Log "< Stored: #{key} -> #{value}"
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
      @debug.Warn "Not ready: #{@ip}:#{@port}"
      return done!

    obj.timestamp = new Date
    obj.sender = @self{hash, port} <<< ip: \localhost
    obj.msgHash = Hash.Create(JSON.stringify obj).Value!

    @client.write JSON.stringify obj

    obj.done = done

    # obj.timer = setTimeout ~>
    #   console.log 'TIMEOUT request' obj
    #   @Disconnect!
    # , 10000

    @waitingAnswers[obj.msgHash] = obj


  Disconnect: ->
    clearInterval @ping_timer
    @client.destroy! if not @client?.destroyed
    @emit 'disconnected'
    # console.log 'Disconnected: ' @ip, @port


  Serialize: ->
    @{hash, ip, port}

  @Deserialize = (it, self, client) ->
    if not it?
      new @ null, null, null, self, client
    else
      hash = (new Hash it.hash.value.data)
      found = self.routing.FindOneNode hash
      if found?
        that
      else
        new @ it.ip, it.port, hash, self, client

module.exports = Node
