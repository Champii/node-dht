require! {
  async
  crypto
  \./ : Dht
  \./Hash
}

node = new Dht 12000, 'nodulator2.champii.io', 5000

node.on \bootstraped ->
  async.mapSeries [1 to process.argv[2] || 10], (i, done) ->
    setTimeout ->
      console.log i
      v = crypto.randomBytes 32 .toString \hex
      hash = Hash.Create v
      node.Store hash, v, ->
      done!
    , 333
  , (err, res) ->
    console.log err || 'OK'
    # process.exit 0
