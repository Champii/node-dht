require! {
  crypto
  \bitwise-xor
}

class Hash

  @LENGTH = 160

  (@value) ->
    if not Buffer.isBuffer @value
      @value = new Buffer @value, \hex

  CountSameBits: (hash) ->
    count = 0
    for v, i in @value
      for k from 0 to 7
        tmpV = v .&. (0x1 .<<. k)
        tmpH = hash.value[i] .&. (0x1 .<<. k)
        if tmpV is tmpH
          count++
        else
          return count
    count

  DistanceTo: (hash) ->
    bitwise-xor @value, hash.value

  Value: ->
    @value.toString it || \hex

  @CreateRandom = -> new this crypto.randomBytes @LENGTH / 8

  @Deserialize = ->
    new @ it.value.data

  @Create = ->
    hash = crypto.createHash \sha1
    hash.update it
    new @ hash.digest!

module.exports = Hash
