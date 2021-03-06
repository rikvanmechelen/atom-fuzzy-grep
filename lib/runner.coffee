{BufferedProcess} = require 'atom'

module.exports =
  class Runner
    commandString: null
    process: null
    useGitGrep: false
    columnArg: false
    env: process.env

    constructor: ()->
      atom.config.observe 'atom-fuzzy-projects-grep.grepCommandString', =>
        @commandString = atom.config.get 'atom-fuzzy-projects-grep.grepCommandString'
        @columnArg = @detectColumnFlag()
      atom.config.observe 'atom-fuzzy-projects-grep.detectGitProjectAndUseGitGrep', =>
        @useGitGrep = atom.config.get 'atom-fuzzy-projects-grep.detectGitProjectAndUseGitGrep'

    run: (@search, @rootPath, callback)->
      listItems = []
      if @useGitGrep and @isGitRepo()
        @commandString = atom.config.get 'atom-fuzzy-projects-grep.gitGrepCommandString'
        @columnArg = false
      [command, args...] = @commandString.split(/\s/)
      args.push @search
      args.push "." if command == "grep"
      options = cwd: @rootPath, stdio: ['ignore', 'pipe', 'pipe'], env: @env
      
      stdout = (output)=>
        console.dir(output)
        if listItems.length > atom.config.get('atom-fuzzy-projects-grep.maxCandidates')
          @destroy()
          return
        listItems = listItems.concat(@parseOutput(output))
        callback(listItems)
      stderr = (error)->
        callback([error: error])
      exit = (code)->
        callback([]) if code == 1
      @process = new BufferedProcess({command, exit, args, stdout, stderr, options})
      @process

    parseOutput: (output, callback)->
      items = []
      contentRegexp = if @columnArg then /^(\d+):\s*/ else /^\s+/
      for item in output.split(/\n/)
        break unless item.length
        [path, line, content...] = item.split(':')
        content = content.join ':'
        items.push
          filePath: path
          fullPath: @rootPath + '/' + path
          line: line-1
          column: @getColumn content
          content: content.replace(contentRegexp, '')
      items

    getColumn: (content)->
      if @columnArg
        return content.match(/^(\d+):/)?[1] - 1
      # escaped characters in regexp can cause error
      # skip it for a while
      try
        match = content.match(new RegExp(@search, 'gi'))?[0]
      catch error
        match = false
      if match then content.indexOf(match) else 0

    destroy: ->
      @process?.kill()

    isGitRepo: ->
      atom.project.repositories.some (item)=>
        @rootPath?.startsWith(item.repo?.workingDirectory) if item

    detectColumnFlag: ->
      /(ag|pt|ack|rg)$/.test(@commandString.split(/\s/)[0]) and ~@commandString.indexOf('--column')

    setEnv: (@env)->
