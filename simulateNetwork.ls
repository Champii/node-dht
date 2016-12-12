require! {
  async
  child_process: { spawn }
}

spawn \lsc <[Runner -l 5000]>

start = 5001
finish = start + (+process.argv[2] || 10)

setTimeout ->

  async.mapSeries [start til finish], (i, done) ->
    setTimeout ->
      client = spawn \lsc [\Runner \-l i, \-p \5000]

      client.stdout.pipe process.stdout
      client.stderr.pipe process.stdout

      printProgess i

      done!

    , 1000
  , (err, res) ->
    console.log err || 'OK'

, 5000

printProgess = (i) ->
  nb = i - start
  str = "#{nb}/#{finish - start}"
  str = '\b' * str.length + str
  process.stdout.write str