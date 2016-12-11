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

defaultConfig =
  maxStoreSize:        1Mo
  replicationInterval: 600sec
  pingInterval:        600sec
  connectTimeout:      10sec

class DhtNode extends EventEmitter

  (@port = 12345, bootstrapIp, bootstrapPort, @config = {}) ->
    @store = {}

    @config = defaultConfig <<< @config

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

    @timer = setInterval ~>
      @ReplicateStore!
    , @config.replicationInterval * 1000

  ReplicateStore: ->
    pairs = obj-to-pairs @store
    async.map pairs, ([key, value], done) ~>
      key = new Hash key

      @Store key, value, done
    , (err) ->
      console.log err if err?

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

    findQueue = async.queue (node, done) ~>

      a = 1
      node[method] hash, (err, res) ~>
        console.log a++ if a > 1
        return done! if err? or not res?

        if res.key?
          @debug.Warn "Found key"
          findQueue.kill!
          finalDone null, null, res.value
          finalDone := ->
          @debug.Log "= Key is found: #{res.key}"
          return done!

        nodes = res
          |> map ~> Node.Deserialize it, @
          |> compact
          # |> filter ~> not @routing.HasNode it
          # |> each console.log
          |> filter ~> it.hash.Value! isnt @hash.Value!
          |> filter (node) ~> not find (~> it.hash.value === node.hash.value), rejected ++ best

        if not nodes.length
          return done!

        async.mapSeries nodes, (node, done) ~>
          @ConnectNewNode node, best, rejected, findQueue, done
        , (err, val) ~>
          done err

    , 3

    each findQueue~push, bucket

    findQueue.drain = ~>
      finalDone null, best

  ConnectNewNode: (node, best, rejected, findQueue, done) ->
    cb = (err) ->
      if err
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

  Store: (key, value, done) ->
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

  calcStoreSize: ->
    @store
      |> obj-to-pairs
      |> fold ((i, j) -> i + j.0.length + j.1.length), 0

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
    if not node?
      return

    # client.on \error ->

DhtNode.Hash = Hash

module.exports = DhtNode
