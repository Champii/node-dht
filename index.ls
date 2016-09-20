global import require \prelude-ls

require! {
  net
  async
  events : EventEmitter
  \./Hash
  \./Routing
  \./Node
}

class DhtNode extends EventEmitter

  (@port = 12345, bootstrapIp, bootstrapPort) ->
    @store = {}

    # process.on 'exit' @~ExitHandler
    # process.on 'SIGINT' @~ExitHandler
    # process.on 'uncaughtException' @~ExitHandler

    @hash = Hash.CreateRandom!
    # console.log "Own hash: " @hash
    @routing = new Routing @

    @server = net.createServer ~>
      @SetProtocole it

    @server.on \error console.error
    @server.listen @port

    if bootstrapIp and bootstrapPort
      @Bootstrap bootstrapIp, bootstrapPort

  ExitHandler: ->
    console.log it.stack
    # Redispatch stored
    # process.exit!

  Bootstrap: (ip, port) ->
    node = new Node ip, port, null, @
    node.Ping (err) ~>
      # console.log 'Bootstrap start'
      return console.error err if err?

      @Find @hash, \FindNode (err, bucket) ~>
        @emit \bootstraped
        # console.log 'Bootstrap Finish'

  FindNode: (hash, done) ->
    @Find hash, \FindNode, done

  FindValue: (key, done) ->
    # hash = Hash.Create key

    @Find key, \FindValue, done

  Find: (hash, method, finalDone) ->
    bucket = @routing.FindNode hash

    best = []
    rejected = []
    findQueue = async.queue (node, done) ~>
      @routing.StoreNode node
      node[method] hash, (err, res) ~>
        return if err?

        if res.key?
          findQueue.kill!
          finalDone null, null, res.value
          finalDone := ->

        res
          |> map ~> Node.Deserialize it, @
          |> filter ~> it.hash.value !== @hash.value
          |> filter (node) ~> not find (~> it.hash.value === node.hash.value), rejected ++ best
          |> map ~>
            if best.length < Hash.LENGTH
              best.push it
              findQueue.push it
            else
              max = maximum-by (~> it.hash.DistanceTo hash), best
              if max.hash.DistanceTo(hash) > it.hash.DistanceTo(hash)
                rejected.push best.splice (find-index (-> it.hash.value === max.hash.value), best), 1
                best.push it
                findQueue.push it
              else
                rejected.push it

        done!
    , 3

    each findQueue~push, bucket

    findQueue.drain = ->
      finalDone null, best

  Store: (key, value, done) ->
    # hash = Hash.Create key

    @FindNode key, (err, bucket) ~>
      return done err if err?

      async.map bucket, (node, done) ~>
        node.Store key, value, (err, res) -> done null err || res
      , (err, res) ->
        done null, "Ok (#{filter (-> it is \Ok ), res .length})"

  StoreLocal: ({{key, value: v}:value}) ->
    key = Hash.Deserialize key

    @store[key.value.toString \hex] = v
    \Ok

  FindValueLocal: (key) ->
    key = Hash.Deserialize key
    if @store[key.value.toString \hex]?
      [that,]
    else
      [, @routing.FindNode key]

  SetProtocole: (client) ->
    client.on \data ~>
      it = JSON.parse it
      @routing.StoreNode Node.Deserialize it.sender, @

      switch it.msg
        | \PING       => @Send client, msg: \PONG
        | \FIND_NODE  => @Send client, msg: \FOUND_NODE value: map (.Serialize!), @routing.FindNode new Hash it.value
        | \STORE      => @Send client, msg: \STORED value: @StoreLocal it
        | \FIND_VALUE =>
          [value, bucket] = @FindValueLocal it

          if value?
            @Send client, msg: \FOUND_VALUE value: key: it.value, value: value
          else if bucket?
            @Send client, msg: \FOUND_NODE value: map (.Serialize!), bucket
        | _           => @emit \unknownMsg, it

    client.on \error console.error

  Send: (client, obj) ->
    obj.sender = @{hash, port} <<< ip: \localhost
    client.write JSON.stringify obj

DhtNode.Hash = Hash

module.exports = DhtNode
