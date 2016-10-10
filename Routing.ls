require! {
  \./Debug
  \./Hash
}

class Routing

  @k = Hash.LENGTH / 8bits

  (@self) ->
    @debug = new Debug "DHT::Routing", Debug.colors.blue
    @blackList = []
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
    @debug.Log "= Find node: #{hash.Value!} in bucket nb #{bucketNb}"
    while bucket.length < @@k and bucketNb >= 0
      if @lists[bucketNb].length
        for v in @lists[bucketNb]
          bucket.push v
          if bucket.lengh >= @@k
            break
      bucketNb--

    # console.log 'Found bucket' bucket
    bucket

  #Returns one node
  FindOneNode: (hash) ->
    @lists
      |> flatten
      |> find (.hash.value === hash.value)

  StoreNode: (node) ->
    if not node.hash? or @HasNode node or @IsBlacklisted node or node.hash.Value! is @self.hash.Value!
      return

    bucketNb = node.hash.CountSameBits @self.hash
    if @lists[bucketNb].length is @@k
      @_ReplaceIfPossible bucketNb, node
    else
      @lists[bucketNb].push node

    # console.log 'Stored Node' node.ip, node.port
    @debug.Log "= Stored node: #{node.hash.Value!}"

    node.once \disconnected ~>
      bef = @lists[bucketNb].length
      @lists[bucketNb] = reject (=== node), @lists[bucketNb]
      @debug.Log "= Removed node: #{node.hash.Value!}"
      aft = @lists[bucketNb].length
      @blackList.push node{ip, port}
      # if bef is aft
      #   throw new Error 'WHESH WTF'

  IsBlacklisted: (node) ->
    @blackList
      |> find (=== node{ip, port})

  _ReplaceIfPossible: (bucketNb, node) ->
    oldestNode = @lists[bucketNb] |> minimum-by (.lastSeen)
    oldestNode.Ping ~>
      if it?
        @lists[bucketNb].slice (find-index (-> it.hash is oldestNode.hash), @lists[bucketNb]), 1

module.exports = Routing
