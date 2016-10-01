require! {
  net
  events : EventEmitter
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

  (@ip, @port, @hash, @self) ->
    if is-type \String @port
      @port = +@port

    @ready = false
    @destroyed = false
    @lastSeen = new Date
    @firstSeen = new Date
    @connecting = false

    # @ping_timer = setInterval @~Ping, 10000
    # console.log 'NEW NODE' @ip, @port

    # @Connect!

  Connect: (done = ->) ->
    if @connecting
      return

    @connecting = true
    console.log 'Connect' @ip, @port
    @client = new net.Socket
    @client.setConnTimeout 5000ms
    # console.log 'CreateConnection' @{ip, port}
    # @client = net.createConnection @{ip, port}, ~>
    #   console.log 'Conneccted'

    # @client.setTimeout 600000ms #10mn
    # @client.setTimeout 10000ms #10sec

    @client.once \error ~>
      console.log 'ERROR' it
      # if @client.destroyed
      #   return
      #
      @Disconnect!
      done 'Error'
      done := ->

    @client.once \timeout ~>
      console.log 'Timeout', it
      # if @client.destroyed
      #   return
      #
      @Disconnect!
      done 'timeout'
      done := ->

    @client.once \connect_timeout ~>
      console.log 'Connect Timeout'
      # if @client.destroyed
      #   return

      @Disconnect!
      done 'timeoutConnect'
      done := ->

    @client.connect @{ip, port}, ~>
      console.log 'Connected' @ip, @port
      @ready = true
      @self.routing.StoreNode @
      done!
      done := ->

  Ping: (done = ->) ->
    @_SendMessage msg: \PING, (err, res) ->
      return done err if err?

      done null, res

  FindNode: (hash, done = ->) ->
    @_SendMessage msg: \FIND_NODE value: hash.value, (err, res) ->
      return done err if err?

      done null, res.value

  FindValue: (hash, done = ->) ->
    @_SendMessage msg: \FIND_VALUE value: hash.value, (err, res) ->
      return done err if err?

      done null, res.value

  Store: (key, value, done = ->) ->
    # console.log 'STORE', done
    @_SendMessage msg: \STORE value: {value, key}, (err, res) ->
      return done err if err?

      done null, res.value

  _SendMessage: (obj, done = (->)) ->
    if not @ready
      console.log 'NOT READY' obj
      return

    obj.sender = @self{hash, port} <<< ip: \localhost

    @client.once \data ~>
      # console.log \data it.toString!
      # console.log 'Answer' it.toString!
      @lastSeen = new Date
      it = JSON.parse it.toString!
      @self.routing.StoreNode Node.Deserialize it.sender, @self
      # @client.destroy!
      done null, it

    @client.write JSON.stringify obj


  Disconnect: ->
    clearInterval @ping_timer
    @client.destroy! if not @client?.destroyed
    @emit 'disconnected'
    # console.log 'Disconnected: ' @ip, @port


  Serialize: ->
    @{hash, ip, port}

  @Deserialize = (it, self) ->
    new @ it.ip, it.port, (new Hash it.hash.value.data), self


module.exports = Node
