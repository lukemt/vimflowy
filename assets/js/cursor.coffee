if module?
  utils = require('./utils.coffee')
  constants = require('./constants.coffee')

class Cursor
  constructor: (data, path = null, col = null, moveCol = null) ->
    @data = data

    # a path [root, ...., parent, row]
    @path = path.slice() ? [0, 1]
    # easy access to last element of path
    @row = path[path.length-1]
    @col = col ? 0

    @properties = {}
    do @_getPropertiesFromContext

    # -1 means last col
    @moveCol = moveCol ? col

  clone: () ->
    return new Cursor @data, @path, @col, @moveCol

  from: (other) ->
    @row = other.row
    @path = other.path.slice()
    @col = other.col
    @moveCol = other.moveCol

  # cursorOptions:
  #   - pastEnd:         means whether we're on the column or past it.
  #                      generally true when in insert mode but not in normal mode
  #                      effectively decides whether we can go past last column or not
  #   - pastEndWord:     whether we consider the end of a word to be after the last letter
  #                      is true in normal mode (for de), false in visual (for vex)
  #   - keepProperties:  for movement, whether we should keep italic/bold state

  set: (row, col, cursorOptions) ->
    @row = row
    @path = @data.getCanonicalPath row
    @setCol col, cursorOptions

  setPath: (path, cursorOptions) ->
    @path = path
    do @assert_path
    @row = @path[@path.length - 1]
    @_fromMoveCol cursorOptions

  setRow: (row, cursorOptions) ->
    @row = row
    @path = @data.getCanonicalPath row
    @_fromMoveCol cursorOptions

  setCol: (moveCol, cursorOptions = {pastEnd: true}) ->
    @moveCol = moveCol
    @_fromMoveCol cursorOptions
    # if moveCol was too far, fix it
    # NOTE: this should happen for setting column, but not row
    if @moveCol >= 0
      @moveCol = @col

  _fromMoveCol: (cursorOptions = {}) ->
    len = @data.getLength @row
    maxcol = len - (if cursorOptions.pastEnd then 0 else 1)
    if @moveCol < 0
      @col = Math.max(0, len + @moveCol + 1)
    else
      @col = Math.max(0, Math.min(maxcol, @moveCol))
    if not cursorOptions.keepProperties
      do @_getPropertiesFromContext

  push_path: (new_row) ->
    @path.push new_row
    @row = new_row

  pop_path: () ->
    old_row = do @path.pop
    do @assert_path
    @row = @path[@path.length - 1]
    return old_row

  assert_path: () ->
    if @path.length < 2
      throw "Unexpectedly short path: #{@path}"

  parentRow: () ->
    do @assert_path
    return @path[@path.length - 2]

  _left: () ->
    @setCol (@col - 1)

  _right: () ->
    @setCol (@col + 1)

  left: () ->
    if @col > 0
      do @_left

  right: (cursorOptions = {}) ->
    shift = if cursorOptions.pastEnd then 0 else 1
    if @col < (@data.getLength @row) - shift
      do @_right

  nextVisible: () ->
    path = do @path.slice
    if not @data.collapsed @row
      children = @data.getChildren @row
      if children.length > 0
        path.push children[0]
        return path
    while true
      id = do path.pop
      nextsib = @data.getSiblingAfter path[path.length-1], id
      if nextsib != null
        path.push nextsib
        return path
    return null

  prevVisible: () ->
    path = do @path.slice
    id = do path.pop
    parent = path[path.length - 1]
    prevsib = @data.getSiblingBefore parent, id
    if prevsib != null
      cur = prevsib
      while true
        path.push cur
        if @data.collapsed cur
          break
        children = @data.getChildren cur
        if children.length == 0
          break
        cur = children[children.length - 1]
      return path
    if parent == @data.viewRoot
      return null
    return path

  up: (cursorOptions = {}) ->
    path = do @prevVisible
    if path != null
      @setPath path


  down: (cursorOptions = {}) ->
    path = do @nextVisible
    if path != null
      @setPath path

  backIfNeeded: () ->
    if @col > (@data.getLength @row) - 1
      do @left

  atVisibleEnd: () ->
    if @col < (@data.getLength @row) - 1
      return false
    else

      if (do @nextVisible) != null
        return false
    return true

  nextChar: () ->
    if @col < (@data.getLength @row) - 1
      do @_right
      return true
    else
      path = do @nextVisible
      if path != null
        @setPath path
        @setCol 0
        return true
    return false

  atVisibleStart: () ->
    if @col > 0
      return false
    else
      path = do @prevVisible
      if path != null
        return false
    return true

  prevChar: () ->
    if @col > 0
      do @_left
      return true
    else
      path = do @prevVisible
      if path != null
        @setPath path
        @setCol -1
        return true
    return false

  home: () ->
    @setCol 0
    return @

  end: (cursorOptions = {cursor: {}}) ->
    @setCol (if cursorOptions.pastEnd then -1 else -2)
    return @

  visibleHome: () ->
    children = @data.getChildren @data.viewroot
    if children.length < 1
      throw "Nothing visible!"
    row = children[0]
    @set row, 0
    return @

  visibleEnd: () ->
    row = do @data.lastVisible
    @set row, 0
    return @

  wordRegex = /^[a-z0-9_]+$/i

  isInWhitespace: (row, col) ->
    char = @data.getChar row, col
    return utils.isWhitespace char

  isInWord: (row, col, matchChar) ->
    if utils.isWhitespace matchChar
      return false

    char = @data.getChar row, col
    if utils.isWhitespace char
      return false

    if wordRegex.test char
      return wordRegex.test matchChar
    else
      return not wordRegex.test matchChar

  getWordCheck: (options, matchChar) ->
    if options.whitespaceWord
      return ((row, col) => not @isInWhitespace row, col)
    else
      return ((row, col) => @isInWord row, col, matchChar)

  beginningWord: (options = {}) ->
    if do @atVisibleStart
      return @
    do @prevChar
    while (not do @atVisibleStart) and @isInWhitespace @row, @col
      do @prevChar

    wordcheck = @getWordCheck options, (@data.getChar @row, @col)
    while (@col > 0) and wordcheck @row, (@col-1)
      do @_left
    return @

  endWord: (options = {}) ->
    if do @atVisibleEnd
      if options.cursor.pastEnd
        do @_right
      return @

    do @nextChar
    while (not do @atVisibleEnd) and @isInWhitespace @row, @col
      do @nextChar

    end = (@data.getLength @row) - 1
    wordcheck = @getWordCheck options, (@data.getChar @row, @col)
    while @col < end and wordcheck @row, (@col+1)
      do @_right

    if options.cursor.pastEndWord
      do @_right

    end = (@data.getLength @row) - 1
    if @col == end and options.cursor.pastEnd
      do @_right
    return @

  nextWord: (options = {}) ->
    if do @atVisibleEnd
      if options.cursor.pastEnd
        do @_right
      return @

    end = (@data.getLength @row) - 1
    wordcheck = @getWordCheck options, (@data.getChar @row, @col)
    while @col < end and wordcheck @row, (@col+1)
      do @_right

    do @nextChar
    while (not do @atVisibleEnd) and @isInWhitespace @row, @col
      do @nextChar

    end = (@data.getLength @row) - 1
    if @col == end and options.cursor.pastEnd
      do @_right
    return @

  findNextChar: (char, options = {}) ->
    end = (@data.getLength @row) - 1
    if @col == end
      return

    col = @col
    if options.beforeFound
      col += 1

    found = null
    while col < end
      col += 1
      if (@data.getChar @row, col) == char
        found = col
        break

    if found == null
      return

    @setCol found
    if options.cursor.pastEnd
      do @_right
    if options.beforeFound
      do @_left

  findPrevChar: (char, options = {}) ->
    if @col == 0
      return

    col = @col
    if options.beforeFound
      col -= 1

    found = null
    while col > 0
      col -= 1
      if (@data.getChar @row, col) == char
        found = col
        break

    if found == null
      return

    @setCol found
    if options.beforeFound
      do @_right

  parent: (cursorOptions = {}) ->
    row = @data.getParent @row
    if row == @data.root
      return
    if row == @data.viewRoot
      @data.changeViewRoot @data.getParent row
    @setRow row, cursorOptions

  prevSibling: (cursorOptions = {}) ->
    prevsib = @data.getSiblingBefore @row
    if prevsib != null
      @setRow prevsib, cursorOptions

  nextSibling: (cursorOptions = {}) ->
    nextsib = @data.getSiblingAfter @row
    if nextsib != null
      @setRow nextsib, cursorOptions

  # cursor properties

  setProperty: (property, value) ->
    @properties[property] = value

  getProperty: (property) ->
    return @properties[property]

  toggleProperty: (property) ->
    @setProperty property, (not (@getProperty property))

  # get whether the cursor should be bold/italic based on surroundings
  # NOTE: only relevant for insert mode.
  _getPropertiesFromContext: () ->
    line = @data.getLine @row
    if line.length == 0
      obj = {}
    else if @col == 0
      obj = line[@col]
    else
      obj = line[@col-1]
    for property in constants.text_properties
      @setProperty property, obj[property]

# exports
module?.exports = Cursor
