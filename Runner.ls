require! {
  crypto
  \./ : node
  \./Hash
}

class Runner

  (@port = 12345, bootstrapIp, bootstrapPort) ->
    # @node = new DhtNode @port, bootstrapIp, bootstrapPort

    @node = node
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
      | '' => process.stdout.write '> '
      | _  => process.stdout.write "Unknown command. Type 'h' for help\n> "

  DisplayHelp: ->
    console.log "
       h           -- help    -- Display this help                   \n
       g KEY       -- get     -- Get a value from a key              \n
       p KEY VALUE -- put     -- Put a key/value pair                \n
       s           -- storage -- Display localy stored keys/values   \n
       r           -- routing -- Display local routing table
    "
    process.stdout.write '> '

  DisplayStore: ->
    for k, value of @node.store
      console.log "#k : #value"
    process.stdout.write '> '

  DisplayRouting: ->
    for bucket, i in @node.routing.lists
      for node in bucket
        console.log "#i : #{node.hash.value.toString \hex }"
    process.stdout.write '> '

  Put: ([, key, value]) ->
    return process.stdout.write 'Invalid syntax: > p key value\n> ' if not key? or not value?

    @node.Store key, value, (err, value) ->
      return console.error err if err?

      console.log value
      process.stdout.write '> '

  Get: ([, key]) ->
    return console.error 'Invalid syntax: > g key' if not key?

    @node.FindValue key, (err, bucket, value) ->
      return process.stdout.write 'Not found\n> ' if bucket? or err?
      console.log "#key : #value" if value?
      process.stdout.write '> '

new Runner process.argv[2], process.argv[3], process.argv[4]
