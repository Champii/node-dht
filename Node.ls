require! {
  net
  \./Hash
}

class Node

  (@ip, @port, @hash, @self) ->
    @lastSeen = new Date
    @firstSeen = new Date

  Ping: (done) ->
    @_SendMessage msg: \PING, (err, res) ->
      return done err if err?

      done null, res.value

  FindNode: (hash, done) ->
    @_SendMessage msg: \FIND_NODE value: hash.value, (err, res) ->
      return done err if err?

      done null, res.value

  FindValue: (hash, done) ->
    @_SendMessage msg: \FIND_VALUE value: hash.value, (err, res) ->
      return done err if err?

      done null, res.value

  Store: (key, value, done) ->
    @_SendMessage msg: \STORE value: {value, key}, (err, res) ->
      return done err if err?

      done null, res.value

  _SendMessage: (obj, done) ->
    obj.sender = @self{hash, port} <<< ip: \localhost

    client = net.connect ip: @ip, port: @port, ->
      client.write JSON.stringify obj

    client.on \data ~>
      it = JSON.parse it
      @self.routing.StoreNode Node.Deserialize it.sender, @self
      done null, it


    client.on \error ->
      done \timeout
    client.on \timeout ->
      done \timeout

  Serialize: ->
    @{hash, ip, port}

  @Deserialize = (it, self) ->
    new @ it.ip, it.port, (new Hash it.hash.value.data), self


module.exports = Node
