require! debug

debug.depth = 0
debug.longuest = 0

class Debug

  @depthActivated = false

  depthStr: ''

  @colors =
    cyan: debug.colors[0]
    green: debug.colors[1]
    yellow: debug.colors[2]
    blue: debug.colors[3]
    purple: debug.colors[4]
    red: debug.colors[5]

  (@name, color = debug.colors[1], objDebug = false) ->

    debug.longuest = max debug.longuest, @name.length + 7

    @_out = debug @name + '::Log'
      ..color = debug.useColors && color
    @_outWarn = debug @name + '::Warn'
      ..color = debug.useColors && @@colors.yellow
    @_outError = debug @name + '::Error'
      ..color = debug.useColors && @@colors.red

  _DepthStr: -> ['.' for i from 0 til debug.depth]*''
  _Padding: -> [' ' for i from 0 til debug.longuest - @name.length - it]*''

  Log: -> @_out @_Padding(5) + @_DepthStr! + it
  Warn: -> @_outWarn @_Padding(6) + @_DepthStr! + it
  Error: -> @_outError @_Padding(7) + @_DepthStr! + it

  @Depth = -> debug.depth = debug.depth + 1 if @depthActivated
  @UnDepth = -> debug.depth = debug.depth - 1 if @depthActivated

module.exports = Debug

# Add debug for objects with utils.debug
