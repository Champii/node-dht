require! {
  crypto
  moment
  commander: argv
  \./ : Dht
  \./Hash
  \./Node
}

argv
  .version '0.0.1'
  .option  '-l, --listen <port>'    'Change listening port (default = 12345)'

  .option  '-h, --host <host>'      'Connect to boostrap node host'
  .option  '-p, --port <port>'      'Connect to boostrap node port'

  .option  '-s, --stats'            'Live statistics mode'

  .parse   process.argv

argv.listen = argv.listen || 12345

if argv.host? || argv.port?
  argv.host = argv.host || 'localhost'
  argv.port = argv.port || 12345

lastInReq = 0
inFlow = 0
lastOutReq = 0
outFlow = 0

setInterval ->
 inFlow := Node.inRequests - lastInReq
 lastInReq := Node.inRequests
 outFlow := Node.outRequests - lastOutReq
 lastOutReq := Node.outRequests
, 1000

prompt = -> process.stdout.write '> ' if not argv.stats

class Runner

  (@port = 12345, bootstrapHost, bootstrapPort) ->
    # @node = new DhtNode @port, bootstrapHost, bootstrapPort

    @node = new Dht @port, bootstrapHost, bootstrapPort
    prompt!
    if argv.stats
      setInterval ~>
        @DisplayInfo!
      , 1000
    else
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
      | '' => prompt!
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

    prompt!

  DisplayInfo: ->
    toLog = "
      --------------------------------------------------------------------------\n
      Hash:             #{@node.hash.Value!}                                    \n
      Uptime:           #{moment @node.startDate .fromNow!}                     \n
      Listening port:   #{argv.listen}                                          \n
      --------------------------------------------------------------------------\n
    "
    if argv.host || argv.port
      toLog += "
      Bootstrap host:   #{argv.host || 'localhost'}                             \n
      Bootstrap port:   #{argv.port || '12345'}                                 \n
      --------------------------------------------------------------------------\n
    "

    toLog += "
      Stored keys:      #{keys @node.store .length} (#{(@node.calcStoreSize! / 2^7) .toFixed 1 }Ko) \n
      Max store size:   #{@node.config.maxStoreSize}Mo                          \n
      --------------------------------------------------------------------------\n
      Connected nodes:  #{flatten @node.routing.lists .length}                  \n
      Total in:         #{Node.inRequests} req                                  \n
      Total out:        #{Node.outRequests} req                                 \n
      req/s (in):       #{inFlow} req/s                                         \n
      req/s (out):      #{outFlow} reqs/s                                       \n
      Avg. req/s (in):  #{Math.floor Node.inRequests / (new Date() - @node.startDate) * 1000} req/s  \n
      Avg. req/s (out): #{Math.floor Node.outRequests / (new Date() - @node.startDate) * 1000} req/s \n
      --------------------------------------------------------------------------\n
    "

    if argv.stats
      console.log('\033[2J');

    console.log toLog
    prompt!

  DisplayStore: ->
    for k, value of @node.store
      console.log "#{k} : #{value.value}"
    prompt!

  DisplayRouting: ->
    for bucket, i in @node.routing.lists
      for node in bucket when node.ready
        console.log "#{i} : #{node.hash.value.toString \hex }"
    prompt!

  Put: ([, key, value]) ->
    return process.stdout.write 'Invalid syntax: > p key value\n> ' if not key? or not value?

    hash = Hash.Create key
    @node.Store hash, value, (err, value) ->
      return console.error err if err?

      console.log value
      prompt!

  Get: ([, key]) ->
    return console.error 'Invalid syntax: > g key' if not key?

    hash = Hash.Create key
    @node.FindValue hash, (err, bucket, value) ->
      return process.stdout.write 'Not found\n> ' if bucket? or err?
      console.log "#{key} : #{value}" if value?
      prompt!

new Runner argv.listen, argv.host, argv.port
