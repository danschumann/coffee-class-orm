_ = require 'underscore'

class CoffeeClassOrm

  @where: (where, options, done) ->
    unless done
      done = options
      options = {}
    @select (_.extend options, {where}), done

  fetch_all: (options = {}, done) ->

    if _.isFunction options
      options = {}
      done = arguments[0]

    @select_all options, (json) =>

      if options is 'by_id' or options.by_id
        collection = []
        _.each json, (instance_data, id) =>
          collection[id] = new @constructor instance_data

        done collection
      else
        done json
    this
    
  recreate: (done) ->

    @db_destroy_table =>
      console.log 'destroyed table'.red
      console.log arguments...
      @db_create_table =>
        console.log 'created table'.green
        console.log arguments...
        done?()
  
  save: ->

    unless @values.id
      @create @values, arguments...
    else
      values = _.pick @values, (_.keys @columns)...
      @update {where: {id: @values.id}}, values, arguments...

  constructor: (@values = {}) ->

    @id = @values.id
    _.extend this, @instance_methods
    # TODO: getters and setters
    #_.extend this, @values

    # adds res.flash
    console.log 'created model'.green

  COLUMN_TYPES: [ 'integer', 'tinyint', 'float', 'varchar', 'text', 'datetime', 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP']

  db_destroy_table: (done) ->

    console.log 'Dropping table'
    mysql.query "DROP TABLE `#{@table_name}`", (err, status) =>
      console.log 'Dropped table', err, status
      console.log 'Dropped table'.red
      done arguments...


  @db_create_table: ({force, engine} = {}, done) ->

    done = arguments[0] if _.isFunction arguments[0]
    done ?= =>
    engine ?= 'InnoDB'
    success = true
    fail = => success = false

    @::columns.id ?=
      type: 'integer'
      primary: true
      required: true

    primary_key = ''

    columns = (_.map @::columns, ({type, len, required, unique, primary}={}, name) =>

      #unless (_ @COLUMN_TYPES).include type
        #console.log "Column type: `#{type}` is not understood by cubechute".red
        #return fail()
      if len?
        len = "(#{len})"
      else
        len = ''
      
      required = if required then ' not null' else ''
      unique = if unique then ' unique' else ''
      autoinc = if primary then ' auto_increment' else ''

      primary_key = name if primary

      "`#{name}` #{type}#{len}#{required}#{autoinc}#{unique}"
    .join ', \n ')

    indexes = [ "PRIMARY KEY ( `#{primary_key}` )" ]
    _.each @::unique_indexes, ([columns...], name) =>
      columns = _.map columns, (cname) =>
        "`#{cname}`"
      indexes.push "UNIQUE KEY `#{name}` (#{columns.join ', '})"

    console.log 'creating table'.green

    unless success
      console.log 'Could not create table'.red
      return done false

    forced = if force then "DROP TABLE `#{@::table_name}` IF EXISTS;" else ''
    mysql.query str = "#{forced} CREATE TABLE IF NOT EXISTS `#{@::table_name}` (
      #{columns},
      #{indexes.join ', '}
    ) ENGINE=#{engine};", (err, status) =>
      console.log 'err'.red, err if err
      console.log 'created table'.green if status?.affectedRows > 0
      console.log str.blue
      done? arguments...

  select_all: (options, done) ->

    if _.isFunction options
      done = options
      options = {}

    @select options, (err, results) =>
      byId = []
      (_ results).each (row) =>
        byId[row.id] = row
      done byId

  # where: ['a = ?', 'Eyy'] , or  {a: 'Eyy'}
  update: (options, values,  done) ->
    
    {where, limit} = options
    if _.isFunction(values)
      done = values
      values = options
      where = {@id, limit: 1}

    _.extend @values, values
      
    where_critera = []

    if _.isArray values
      [values_clause, where_args...] = values
      where_critera.push where_args...
    else
      values_clause = (_.map values, (val, column) =>
        where_critera.push val

        "#{column} = ?"
      .join ', ')

    if _.isArray where
      [where_clause, where_args...] = where
      where_critera.push where_args
    else
      where_clause = (_.map where, (val, column) =>
        where_critera.push val

        "#{column} = ?"
      .join ' and ')
    
    
    str = "update #{@table_name} set #{values_clause}
#{ if where? then (' where ' + where_clause) else ''}
#{ if limit? then (' limit ' + parseInt(limit)) else '' } 
    "
    console.log str
    console.log where_critera
    console.log 'query string'.blue

    #  HACK: We're letting mysql do sanitization
    mysql.query str, where_critera, (err, results) ->
      done err, results

  find: (id, done) -> @select {limit: 1, where: {id}}, done

  hasMany: (Class, {as}) ->
    
    @_hasMany ?= []
    @_hasMany.push arguments

  # columns: string or arrays of string # default *
  # join: ['left join a on a.a = ?', 'Eyy']
  # where: ['a = ?', 'Eyy'] , or  {a: 'Eyy'}
  # limit: 1 will cause results to be object instead of array
  @select: ({columns, tables, where, join, limit} = {}, done) ->


    done = arguments[0] if _.isFunction arguments[0]

    # all escaped variables are added at once, starting with joins
    [join, where_critera...] = join if _.isArray join
    where_critera ?= []
  
    # then the where clause
    if _.isArray where
      [where_clause, where_args...] = where
      where_critera.push where_args...
    else
      where_clause = (_.map where, (val, column) =>
        where_critera.push val
        "#{column} = ?"
      .join ' and ')

    columns = columns.join(', ') if _.isArray columns
    
    str = "select #{columns ? '*'}
 from #{@::table_name}
#{if tables? then ', '+tables.join(', ') else ''}
#{ if join? then ' '+join else ''}
#{ if where? then ' where '+where_clause else ''}
#{ if limit? then ' limit '+parseInt(limit) else '' } 
    "
    console.log str.blue
    console.log arguments...
    console.log where_critera

    #  HACK: We're letting mysql do sanitization
    mysql.query str, where_critera, (err, results) ->

      if limit == 1 and results? then results = results[0]
      done err, results

  describe: (done) ->
    
    mysql.query "describe #{@table_name}", done

  create: (columns, done) ->

    mysql.query sql = "insert into #{@table_name} (#{
      (_ columns).keys().join(', ')
    }) values (#{
      (_.map [0..._.size columns], -> '?').join(', ')
    })", (_ columns).values(), (err, status) =>
      if err
        console.log 'error creating'.red
        console.log err.red
      else
        @id = @values.id = status.insertId
      #console.log 'doing done', done
      done err, status
    console.log sql, columns


module.exports = CoffeeClassOrm
