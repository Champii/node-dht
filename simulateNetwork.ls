spawn = require 'child_process' .spawn

spawn \lsc <[Runner 5000]>

for i from 5001 til 5001 + (+process.argv[2] || 10)
  client = spawn \lsc [\Runner i, \localhost \5000]
  client.on \error console.log
