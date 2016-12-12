global import require \prelude-ls

require! {
  net
  async
  moment
  events : EventEmitter
  \./Debug
  \./Hash
  \./Routing
  \./Node
}

defaultConfig =
  maxStoreSize:        20Mo
  maxEntrySize:        1024Ko

  replicationInterval: 600sec
  pingInterval:        600sec
  connectTimeout:      10sec
  concurrentWorkers:   3
  timerRandomWindow:   10000ms

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

    @startDate = new Date

    if bootstrapIp and bootstrapPort
      @debug.Log "Bootstraping to #{bootstrapIp}:#{bootstrapPort}"
      @Bootstrap bootstrapIp, bootstrapPort
    else
      @debug.Log "Starting in mode bootstrap"

    @timer = setInterval ~>
      @ReplicateStore!
    , 10000 #10sec

  RandomizeTime: ->
    (Math.random() * @config.timerRandomWindow) - (@config.timerRandomWindow / 2)

  ReplicateStore: ->
    pairs = obj-to-pairs @store
    async.map pairs, ([key, obj], done) ~>
      key = new Hash key

      timeEnd = moment(obj.storedAt).add(@config.replicationInterval, \seconds )

      if timeEnd < moment()
        @Store key, obj.value, done
        obj.storedAt = new Date
      else
        done!

    , (err) ->
      console.log err if err?

  ExitHandler: ->
    console.log it.stack
    # Redispatch stored
    # process.exit!

  Bootstrap: (ip, port) ->
    node = new Node ip, port, null, @
    node.Connect (err) ~>
      return console.error 'Connect error' err if err?


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

      node[method] hash, (err, res) ~>
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
          |> filter (node) ~> not find (~> it?hash?value === node.hash.value), rejected ++ best

        if not nodes.length
          return done!

        async.mapSeries nodes, (node, done) ~>
          # console.log 'LOL' hash
          @ConnectNewNode node, best, rejected, findQueue, hash, done
        , (err, val) ~>
          done err

    , @config.concurrentWorkers

    each findQueue~push, bucket

    findQueue.drain = ~>
      finalDone null, best

  ConnectNewNode: (node, best, rejected, findQueue, hash, done) ->
    # console.log hash
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
    entrySize = (key.Value!length + v.length) / 1024 #ko
    storeSize = @calcStoreSize! / 1024 / 1024 #mo
    # console.log storeSize, entrySize / 1024, @config.maxStoreSize

    if entrySize > @config.maxEntrySize
      return @debug.Warn "! Impossible to store entry: Entry is too big: #{entrySize}Ko. Max is #{@config.entrySize}"

    if storeSize + (entrySize / 1024) > @config.maxStoreSize
      return @debug.Warn "! Impossible to store entry: store is full (#{storeSize.toFixed 2}/#{@config.maxStoreSize}Mo)"

    @store[key.value.toString \hex] =
      value: v
      storedAt: moment!.add @RandomizeTime!, 'milliseconds'

    @debug.Log "= Stored localy: #{key.Value!}"
    \Ok

  calcStoreSize: ->
    @store
      |> obj-to-pairs
      |> fold ((i, j) -> i + j.0.length + j.1.value.length), 0

  FindValueLocal: (key) ->
    key = Hash.Deserialize key

    if @store[key.value.toString \hex]?
      @debug.Log "= Found value localy: #{key.Value!}"
      [that.value,]
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
