spawn = require 'child_process' .spawn

spawn \lsc <[. 5000]>

for i from 5001 til 5001 + (+process.argv[2] || 10)
  spawn \lsc [\. i, \localhost \5000]
