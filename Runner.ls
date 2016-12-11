require! {
  crypto
  \./ : Dht
  \./Hash
}

class Runner

  (@port = 12345, bootstrapIp, bootstrapPort) ->
    # @node = new DhtNode @port, bootstrapIp, bootstrapPort

    @node = new Dht @port, bootstrapIp, bootstrapPort
    process.stdout.write '> '
    process.stdin.on \data @~Dispatch

  Dispatch: ->
    return process.stdout.write "Unknown command. Type 'h' for help.\n> " if not it?
    it = new Buffer it[til -1]

    switch (it.toString!split ' ').0
      | \h => @DisplayHelp!
      | \r => @DisplayRouting!
      | \p => @Put (it.toString!split ' ')
      | \g => @Get (it.toString!split ' ')
      | \s => @DisplayStore!
      | \i => @DisplayInfo!
      | '' => process.stdout.write '> '
      | _  => process.stdout.write "Unknown command. Type 'h' for help\n> "

  DisplayHelp: ->
    console.log "
      ----------------------------------------------------------------\n
      - h           -- help    -- Display this help                   \n
      - g KEY       -- get     -- Get a value from a key              \n
      - p KEY VALUE -- put     -- Put a key/value pair                \n
      - s           -- storage -- Display localy stored keys/values   \n
      - r           -- routing -- Display local routing table         \n
      - i           -- infos   -- Display general node infos          \n
      ----------------------------------------------------------------\n
    "

    process.stdout.write '> '

  DisplayInfo: ->
    console.log "
      Hash:             #{@node.hash.Value!}                                    \n
      Connected nodes:  #{flatten @node.routing.lists .length}                  \n
      Stored keys:      #{keys @node.store .length} (#{(@node.calcStoreSize! / 2^7) .toFixed 1 }Ko) \n
    "
    process.stdout.write '> '

  DisplayStore: ->
    for k, value of @node.store
      console.log "#{k} : #{value}"
    process.stdout.write '> '

  DisplayRouting: ->
    for bucket, i in @node.routing.lists
      for node in bucket when node.ready
        console.log "#{i} : #{node.hash.value.toString \hex }"
    process.stdout.write '> '

  Put: ([, key, value]) ->
    return process.stdout.write 'Invalid syntax: > p key value\n> ' if not key? or not value?

    hash = Hash.Create key
    @node.Store hash, value, (err, value) ->
      return console.error err if err?

      console.log value
      process.stdout.write '> '

  Get: ([, key]) ->
    return console.error 'Invalid syntax: > g key' if not key?

    hash = Hash.Create key
    @node.FindValue hash, (err, bucket, value) ->
      return process.stdout.write 'Not found\n> ' if bucket? or err?
      console.log "#{key} : #{value}" if value?
      process.stdout.write '> '

new Runner process.argv[2], process.argv[3], process.argv[4]
