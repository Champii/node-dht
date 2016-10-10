global import require \prelude-ls

require! {
  net
  async
  events : EventEmitter
  \./Debug
  \./Hash
  \./Routing
  \./Node
}

class DhtNode extends EventEmitter

  (@port = 12345, bootstrapIp, bootstrapPort) ->
    @store = {}

    @debug = new Debug 'DHT::Main', Debug.colors.green


    # process.on 'exit' @~ExitHandler
    # process.on 'SIGINT' @~ExitHandler
    # process.on 'uncaughtException' @~ExitHandler

    @hash = Hash.CreateRandom!

    # force max size of debug padding
    new Debug "DHT::Main::#{@hash.Value!}", Debug.colors.green

    @debug.Log "Own node Hash: #{@hash.Value!}"

    # console.log "Own hash: " @hash
    @routing = new Routing @

    @server = net.createServer @~SetProtocole

    @server.on \error -> console.log 'Server error' it
    @server.listen @port
    @debug.Log "Listening to #{@port}"

    if bootstrapIp and bootstrapPort
      @debug.Log "Bootstraping to #{bootstrapIp}:#{bootstrapPort}"
      @Bootstrap bootstrapIp, bootstrapPort
    else
      @debug.Log "Starting in mode bootstrap"

  #   @timer = setInterval ~>
  #     @ReplicateStore!
  #   , 1000
  #
  # ReplicateStore: ->
  #   pairs = obj-to-pairs @store
  #   async.map pairs, (pair, done) ~>
  #     @Store pair.0, pair.1, done
  #   , (err, done) ->
  #     console.log err if err?

  ExitHandler: ->
    console.log it.stack
    # Redispatch stored
    # process.exit!

  Bootstrap: (ip, port) ->
    node = new Node ip, port, null, @
    node.Connect (err) ~>
      return console.error err if err?

      node.Ping (err, value) ~>
        # console.log 'Bootstrap start'
        return console.error err if err?

        node.hash = (new Hash value.sender.hash.value.data)

        @routing.StoreNode node

        @Find @hash, \FindNode (err, bucket) ~>
          return console.error err if err?

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
    # @debug.Log "= Start find: #{hash.Value!} from #{bucket.length} nodes"
    # console.log 'FIND' method
    findQueue = async.queue (node, done) ~>
      # @ConnectNewNode node, best, rejected, findQueue, ->
      #   console.log &
      # @routing.StoreNode node
      # @debug.Log "= Asking #{node.hash.Value!}"
      node[method] hash, (err, res) ~>
        # console.log 'find queue', err, res
        return done! if err? or not res?


        if res.key?
          findQueue.kill!
          finalDone null, null, res.value
          finalDone := ->
          @debug.Log "= Key is found: #{res.key}"
          return done!

        nodes = res
          |> map ~> Node.Deserialize it, @
          # |> filter ~> not @routing.HasNode it
          |> filter ~> it.hash.Value! isnt @hash.Value!
          |> filter (node) ~> not find (~> it.hash.value === node.hash.value), rejected ++ best

        if not nodes.length
          return done!

        async.mapSeries nodes, (node, done) ~>
          @ConnectNewNode node, best, rejected, findQueue, done
        , (err, val) ~>
          done!


    , 3

    each findQueue~push, bucket

    # setTimeout ~>
    #   findQueue.kill!
    # , 1000

    findQueue.drain = ~>
      # console.log 'Finish queue', best
      # @debug.Log "Find finished: #{best.length} nodes"
      finalDone null, best

  ConnectNewNode: (node, best, rejected, findQueue, done) ->
    # console.log 'Connect new node' node.ip, node.port
    cb = (err) ->
      # console.log 'Connected', node.ip, node.port
      if err
        # console.error err
        return done!

      if best.length < Hash.LENGTH
        best.push node
        findQueue.push node
      else
        max = maximum-by (~> it.hash.DistanceTo hash), best
        if max.hash.DistanceTo(hash) > node.hash.DistanceTo(hash)
          rejected.push best.splice (find-index (-> it.hash.value === max.hash.value), best), 1
          best.push node
          findQueue.push node
        else
          rejected.push node

      done!

    node.Connect cb
    # else if not node.connecting
    #   cb!
    # else if node.connecting
    #   console.log 'Connecting'


  Store: (key, value, done) ->
    # hash = Hash.Create key

    @FindNode key, (err, bucket) ~>
      return done err if err?

      async.map bucket, (node, done) ~>
        node.Store key, value, (err, res) -> done null err || res
      , (err, res) ->
        done null, "Ok (#{filter (-> it is \Ok ), res .length}/ #{res.length})"

  StoreLocal: ({{key, value: v}:value}) ->
    key = Hash.Deserialize key

    @store[key.value.toString \hex] = v
    @debug.Log "= Stored localy: #{key.Value!}"
    \Ok

  FindValueLocal: (key) ->
    key = Hash.Deserialize key

    if @store[key.value.toString \hex]?
      @debug.Log "= Found value localy: #{key.Value!}"
      [that,]
    else
      nodes = @routing.FindNode key
      @debug.Log "= Local value not found: forward -> #{nodes.length} nodes"
      [, nodes]

  SetProtocole: (client) ->
    node = Node.Deserialize null, @, client

    client.on \error console.error

  # Send: (client, obj) ->
  #   obj.timestamp = new Date
  #   obj.sender = @{hash, port} <<< ip: \localhost
  #   obj.msgHash = Hash.Create(JSON.stringify obj).Value!
  #
  #   client.write JSON.stringify obj

DhtNode.Hash = Hash

module.exports = DhtNode
