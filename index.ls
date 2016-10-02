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

    @server = net.createServer @~SetProtocole

    @server.on \error -> console.log 'Server error' it
    @server.listen @port

    if bootstrapIp and bootstrapPort
      @Bootstrap bootstrapIp, bootstrapPort

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
    findQueue = async.queue (node, done) ~>
      # @routing.StoreNode node
      node[method] hash, (err, res) ~>
        return done! if err?

        if res.key?
          findQueue.kill!
          finalDone null, null, res.value
          finalDone := ->

        # console.log 'Found' res
        res
          |> map ~> Node.Deserialize it, @
          |> filter ~> not @routing~HasNode it
          |> filter ~> it.hash.value !== @hash.value
          |> filter (node) ~> not find (~> it.hash.value === node.hash.value), rejected ++ best
          |> map (node) ~>
            node.Connect (err) ~>
              return console.error err if err

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
    , 3

    each findQueue~push, bucket

    findQueue.drain = ->
      finalDone null, best

  Store: (key, value, done) ->
    # hash = Hash.Create key

    @FindNode key, (err, bucket) ~>
      return done err if err?
      # console.log 'FOUND' err, bucket

      async.map bucket, (node, done) ~>
        node.Store key, value, (err, res) -> done null err || res
      , (err, res) ->
        # return done err if err?

        done null, "Ok (#{filter (-> it is \Ok ), res .length}/ #{res.length})"

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
      # console.log 'Request' it
      node = Node.Deserialize it.sender, @

      cb = (err) ~>
        return console.error err if err?

        switch it.msg
          | \PING       => @Send client, answerTo: it.msgHash, msg: \PONG
          | \FIND_NODE  => @Send client, answerTo: it.msgHash, msg: \FOUND_NODE value: map (.Serialize!), @routing.FindNode new Hash it.value
          | \STORE      => @Send client, answerTo: it.msgHash, msg: \STORED value: @StoreLocal it
          | \FIND_VALUE =>
            [value, bucket] = @FindValueLocal it

            if value?
              @Send client, answerTo: it.msgHash, msg: \FOUND_VALUE value: key: it.value, value: value
            else if bucket?
              @Send client, answerTo: it.msgHash, msg: \FOUND_NODE value: map (.Serialize!), bucket
          | _           => @emit \unknownMsg, it


      if @routing.FindOneNode node.hash
        node = that
        cb!
      else
        node.Connect cb


    client.on \error console.error

  Send: (client, obj) ->
    obj.timestamp = new Date
    obj.sender = @{hash, port} <<< ip: \localhost
    obj.msgHash = Hash.Create(JSON.stringify obj).Value!

    client.write JSON.stringify obj

DhtNode.Hash = Hash

module.exports = DhtNode
