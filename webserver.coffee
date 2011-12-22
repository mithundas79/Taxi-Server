express = require('express')
winston = require('winston')
mongodb = require('mongodb')
mongoStore = require('connect-mongodb')

######################################################
# mongodb setup
######################################################
db = new mongodb.Db(config.database.db, new mongodb.Server(config.database.host, config.database.port,{auto_reconnect: true, poolSize: 4}))

######################################################
# initiate models
######################################################
User = require('./models/user')
Service = require('./models/service')
Message = require('./models/message')
Evaluation = require('./models/evaluation')
Location = require('./models/location')

User.setup(db)
Service.setup(db)
Message.setup(db)
Evaluation.setup(db)
Location.setup(db)
######################################################
# controllers
######################################################
AuthorizationController = require('./controllers/authorization_controller')
authorization_controller = new AuthorizationController()

DriverController = require('./controllers/driver_controller')
driver_controller = new DriverController()

PassengerController = require('./controllers/passenger_controller')
passenger_controller = new PassengerController()

TaxiCallController = require('./controllers/taxi_call_controller')
taxi_call_controller = new TaxiCallController()

LocationController = require('./controllers/location_controller')
location_controller = new LocationController()

######################################################
# create express
######################################################
module.exports = app = express.createServer()

app.start = ->
  app.db.open ->
    app.listen config.webserver.port, ->
      addr = app.address()
      winston.info('app listening on http://' + addr.address + ':' + addr.port)

app.db = db
######################################################
# configurations
######################################################
app.configure ->
  app.use(express.bodyParser())
  app.use(express.cookieParser())
  app.use express.session
    secret: "keyboard cat"
    maxAge: 60000 * 20
    store: new mongoStore({db: db})

  app.use express.errorHandler
    dumpExceptions: true
    showStack : true

app.configure 'test', ->
  winston.remove(winston.transports.Console)

app.configure 'development', 'production', ->
  # for logging
  winston.add(winston.transports.File, { filename: "#{process.env.NODE_ENV}.log", handleExceptions: true })
  winston.handleExceptions()
  # stub winston to use with logger middleware
  winston.write = (data) -> winston.info(data)
  app.use(express.logger({stream: winston}))

  # don't use scheduler while test
  require('./controllers/scheduler')

  # logging params & response
  app.use (req, res, next) ->
    res.on "finish", ->
      winston.info("params:", req.json_data) if req.json_data

    stub = res.json
    res.json = (data) ->
      winston.info("response:", data)
      stub.apply(res, [data])

    next()

######################################################
# preprocess json data
######################################################
app.use (req, res, next) ->
  if req.param("json_data")
    try
      req.json_data = JSON.parse(req.param("json_data"))
    catch e
      return res.json {status: 2, message:"incorrect format in preprocessing"}

  unless req.session.user_id
    return next()

  User.collection.findOne { phone_number: req.session.user_id }, {}, (err, doc)->
    if doc
      User.collection.update {_id: doc._id}, {$set: {last_active_at: new Date(), state: 2}}
      req.current_user = doc

    next()

# debug routes
app.get '/', (req, res, next)->
  res.json { status: 0, message:"hello, world!" }

######################################################
# driver routes
######################################################
app.post '/driver/signup',          driver_controller.signup
app.post '/driver/signin',          driver_controller.signin
app.post '/driver/signout',         authorization_controller.restrict_to_driver,   driver_controller.signout
app.post '/driver/location/update', authorization_controller.restrict_to_driver,   driver_controller.updateLocation
app.post '/driver/taxi/update',     authorization_controller.restrict_to_driver,   driver_controller.updateState
app.get  '/driver/refresh',         authorization_controller.restrict_to_driver,   driver_controller.refresh

######################################################
# passenger routes
######################################################
app.post '/passenger/signup',           passenger_controller.signup
app.post '/passenger/signin',           passenger_controller.signin
app.post '/passenger/signout',          authorization_controller.restrict_to_passenger,   passenger_controller.signout
app.post '/passenger/location/update',  authorization_controller.restrict_to_passenger,   passenger_controller.updateLocation
app.get  '/passenger/refresh',          authorization_controller.restrict_to_passenger,   passenger_controller.refresh

######################################################
# taxi call routes
######################################################
app.get  '/taxi/near',                authorization_controller.restrict_to_passenger,    taxi_call_controller.getNearTaxis
app.post '/service/create',           authorization_controller.restrict_to_passenger,    taxi_call_controller.create
app.post '/service/reply',            authorization_controller.restrict_to_driver,       taxi_call_controller.reply
app.post '/service/cancel',           authorization_controller.restrict_to_passenger,    taxi_call_controller.cancel
app.post '/service/complete',         authorization_controller.restrict_to_driver,       taxi_call_controller.complete
app.post '/service/evaluate',         authorization_controller.restrict_to_user,         taxi_call_controller.evaluate
app.get  '/service/history',          authorization_controller.restrict_to_user,         taxi_call_controller.history
app.get  '/service/evaluations',      authorization_controller.restrict_to_user,         taxi_call_controller.getEvaluations
app.get  '/service/user/evaluations', authorization_controller.restrict_to_user,         taxi_call_controller.getUserEvaluations

######################################################
# location routes
######################################################
app.post '/location/create',          authorization_controller.restrict_to_user,       location_controller.create
