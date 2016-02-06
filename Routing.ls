require! {
  \./Hash
}

class Routing

  @k = Hash.LENGTH / 8

  (@self) ->
    @lists = map (-> []), [til Hash.LENGTH + 1]

  HasNode: (node) ->
    bucketNb = node.hash.CountSameBits @self.hash
    if find (.hash.value === node.hash.value), @lists[bucketNb]
      return true

    false

  #Returns the k-bucket with k nearest node
  FindNode: (hash) ->
    bucket = []
    bucketNb = hash.CountSameBits @self.hash
    while bucket.length < @@k and bucketNb >= 0
      if @lists[bucketNb].length
        for v in @lists[bucketNb]
          bucket.push v
          if bucket.lengh >= @@k
            break
      bucketNb--

    bucket

  StoreNode: (node) ->
    if @HasNode node
      return

    bucketNb = node.hash.CountSameBits @self.hash
    if @lists[bucketNb].length is @@k
      @_ReplaceIfPossible bucketNb, node
    else
      @lists[bucketNb].push node

  _ReplaceIfPossible: (bucketNb, node) ->
    oldestNode = @lists[bucketNb] |> minimum-by (.lastSeen)
    oldestNode.Ping ~>
      if it?
        @lists[bucketNb].slice (find-index (-> it.hash is oldestNode.hash), @lists[bucketNb]), 1

module.exports = Routing
