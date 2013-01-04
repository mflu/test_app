require 'sinatra'
require 'redis'
require 'json'
require 'mongo'
require 'mysql2'
require 'carrot'
require 'uri'
require 'pg'
require "yajl"
require "digest/md5"

ATMOS_OBJ_PREFIX = "\/rest\/objects\/"

$:.unshift File.join(File.dirname(__FILE__),'lib','atmos')
require 'atmos_client'


get '/env' do
  ENV['VMC_SERVICES']
end

get '/' do
  'hello from sinatra'
end

get '/crash' do
  Process.kill("KILL", Process.pid)
end

put '/service/redis/dbeater/table/:table' do
  params[:table]
end

post '/service/redis/dbeater/:table/:mega' do
  c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
  # prepare 1M data
  content = (0..1000000).map{ c[rand(c.size)] }.join
  begin
  redis = load_redis
  mega_no = params[:mega].to_i
  i = 1
  while i <= mega_no do
    key = "#{params[:table]}_#{i}"
    redis[key] = content
    i += 1
  end
  rescue => e
     "#{e} => #{e.backtrace}"
  end
end

get '/service/redis/dbeater/db/size' do
  begin
    redis = load_redis
    info = redis.info
    size = "Used memory in megabyte: #{info['used_memory'].to_f/1048576} (RSS: #{info['used_memory_rss'].to_f/1048576}) with #{redis.dbsize} keys"
    size
  rescue => e
    "#{e} => #{e.backtrace}"
  end
end

get '/service/redis/:key' do
  redis = load_redis
  redis[params[:key]]
end

post '/service/redis/:key' do
  redis = load_redis
  redis[params[:key]] = request.env["rack.input"].read
end

put '/service/mongodb/dbeater/table/:table' do
  begin
  db = load_mongo
  # table in mongodb is collection
  db.create_collection(params[:table])
  params[:table]
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    params[:table]
 end
end

post '/service/mongodb/dbeater/:table/:mega' do
  c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
  # prepare 1M data
  content = (0..1000000).map{ c[rand(c.size)] }.join
  begin
  db = load_mongo
  mega_no = params[:mega].to_i
  i = 1
  while i <= mega_no do
    coll = db[params[:table]]
    coll.insert({ "key" => Time.now.getutc.to_s ,"value" => content })
    i += 1
  end
  rescue => e
     "#{e} => #{e.backtrace}"
  end
end

post '/service/mongodb/dbeater/checksum/:table/:mega/:start_no' do
  c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
  # prepare 1M data
  begin
  db = load_mongo
  coll = db[params[:table]]

  mega_no = params[:mega].to_i
  i = params[:start_no].to_i
  end_no = i + mega_no - 1
  checksums = ""
  while i <= end_no do
    content = (0..(10000*rand)).map{ c[rand(c.size)] }.join
    coll.insert({ "key" => i.to_s ,"value" => content })
    checksums << "#{i.to_s} #{Digest::MD5.hexdigest(content)}\n"
    i += 1
  end
  checksums
  rescue => e
     "#{e} => #{e.backtrace}"
  end
end

get '/service/mongodb/dbeater/checksum/list/:table/:mega/:start_no' do
  c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
  # prepare 1M data
  begin
  db = load_mongo
  coll = db[params[:table]]

  mega_no = params[:mega].to_i
  i = params[:start_no].to_i
  end_no = i + mega_no - 1
  checksums = ""
  while i <= end_no do
    docs = coll.find('key' => i.to_s)
    values = docs.to_a
    value = values[0]["value"] if values.size > 0
    checksum = Digest::MD5.hexdigest(value.to_s) unless value.nil?
    checksums << "#{i.to_s} #{checksum}\n"
    i += 1
  end
  checksums
  rescue => e
     "#{e} => #{e.backtrace}"
  end
end

get '/service/mongodb/dbeater/checksum/:table/:key' do
  begin
    table = params[:table]
    key = params[:key]
    db = load_mongo
    coll = db[table]
    docs = coll.find('key' => key)
    checksum = ""
    values = docs.to_a
    value = values[0]["value"] if values.size > 0
    checksum = Digest::MD5.hexdigest(value.to_s) unless value.nil?
    checksum
  rescue => e
    "#{e} => #{e.backtrace}"
  end
end

get '/service/mongodb/dbeater/checksum/:table/:key/:checksum' do
  begin
    table = params[:table]
    key = params[:key]
    input_checksum = params[:checksum]
    db = load_mongo
    coll = db[table]
    docs = coll.find('key' => key)
    checksum = ""
    values = docs.to_a
    value = values[0]["value"] if values.size > 0
    checksum = Digest::MD5.hexdigest(value.to_s) unless value.nil?
    if checksum == input_checksum
      "Y"
    else
      "N"
    end
  rescue => e
    "#{e} => #{e.backtrace}"
  end

end

get '/service/mongodb/dbeater/db/size' do
  begin
    db = load_mongo
    size = 0
    db.collections.each do |coll|
      size += coll.count()
    end
    "Total #{size} records"
  rescue => e
    "#{e} => #{e.backtrace}"
  end
end

post '/service/mongodb/:key' do
  coll = load_mongo['data_values']
  value = request.env["rack.input"].read
  if coll.find('_id' => params[:key]).to_a.empty?
    coll.insert( { '_id' => params[:key], 'data_value' => value } )
  else
    coll.update( { '_id' => params[:key] }, { '_id' => params[:key], 'data_value' => value } )
  end
  value
end

get '/service/mongodb/:key' do
  coll = load_mongo['data_values']
  coll.find('_id' => params[:key]).to_a.first['data_value']
end

not_found do
  'This is nowhere to be found.'
end

put '/service/mysql/tmpdir/table/:table' do
  begin
    client = load_mysql
    client.query("create table if not exists #{params[:table]} (id int(11) NOT NULL auto_increment, eid int not null, salary int not null, primary key (id));")
    params[:table]
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    client.close
    params[:table]
  end
end

post '/service/mysql/tmpdir/table/:table/column/:newc' do
  begin
    client = load_mysql
    table = params[:table]
    newc = params[:newc]
    newcc = "#{newc}_new"
    client.query("alter table `#{table}` change `eid` `eeid` int not null ")
    client.query("alter table `#{table}` change `eeid` `eid` int not null ")
    client.query("alter table `#{table}` change `eid` `eeid` int not null ")
    client.query("alter table `#{table}` change `eeid` `eid` int not null ")
    params[:table]
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    params[:table]
  end
end

post '/service/mysql/tmpdir/:table/:num' do
  begin
    client = load_mysql
    table=params[:table]
    num=params[:num]
    num.to_i.times do
      i = (1000000 * rand).to_i
      s = (40000 * rand).to_i + 200
      client.query("insert into #{table} (eid, salary) values (#{i}, #{s});");
    end
    res = client.query("select count(id) as record_num from #{table}");
    res.first["record_num"].to_s
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    client.close
  end
end

get '/service/mysql/tmpdir/:table/order' do
  begin
    client = load_mysql
    table=params[:table]
    res = client.query("select eid, sum(salary) as sum_salary from #{table} group by eid having sum_salary > 0 order by sum_salary desc limit 10;")
    str=""
    res.each do |r|
      str << "#{r['eid']} has #{r['sum_salary'].to_i} > "
    end
    str
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    client.close
  end
end

put '/service/mysql/dbeater/table/:table' do
  begin
  client = load_mysql
  client.query("create table if not exists #{params[:table]} (value longtext);")
  client.query("create procedure defaultfunc(out defaultcount int) begin select count(*) into defaultcount from #{params[:table]}; end")
  params[:table]
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    client.close
    params[:table]
 end
end

post '/service/mysql/dbeater/:table/:mega' do
  c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
  # prepare 1M data
  content = (0..1000000).map{ c[rand(c.size)] }.join
  begin
  client = load_mysql
  mega_no = params[:mega].to_i
  i = 1
  while i <= mega_no do
    client.query("insert into #{params[:table]} (value) values('#{content}');")
    i += 1
  end
  rescue => e
     "#{e} => #{e.backtrace}"
  ensure
    client.close
  end
end

get '/service/mysql/dbeater/db/recordnum' do
  begin
    client = load_mysql
    client.query("call defaultfunc(@recordnum)")
    res = client.query("select @recordnum")
    output = ""
    res.each do |x|
      output << "#{x.to_s}"
    end
    output
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
   client.close
  end
end

get '/service/mysql/dbeater/db/size' do
  begin
  client = load_mysql
  db_size = mysql_db_size(client, db_name("mysql"))
  db_size
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
   client.close
  end
end

post '/service/mysql/:key' do
  client = load_mysql
  value = request.env["rack.input"].read
  key = params[:key]
  result = client.query("select * from data_values where id='#{key}'")
  if result.count > 0
    client.query("update data_values set data_value='#{value}' where id='#{key}'")
  else
    client.query("insert into data_values (id, data_value) values('#{key}','#{value}');")
  end
  client.close
  value
end

get '/service/mysql/:key' do
  client = load_mysql
  result = client.query("select data_value from  data_values where id = '#{params[:key]}'")
  value = result.first['data_value']
  client.close
  value
end

put '/service/mysql/table/:table' do
  client = load_mysql
  client.query("create table #{params[:table]} (x int);")
  client.close
  params[:table]
end

delete '/service/mysql/:object/:name' do
  client = load_mysql
  client.query("drop #{params[:object]} #{params[:name]};")
  client.close
  params[:name]
end

put '/service/mysql/function/:function' do
  client = load_mysql
  client.query("create function #{params[:function]}() returns int return 1234;");
  client.close
  params[:function]
end

put '/service/mysql/procedure/:procedure' do
  client = load_mysql
  client.query("create procedure #{params[:procedure]}() begin end;");
  client.close
  params[:procedure]
end

helpers do
  def parse_env(service_type)
    svcs = ENV['VMC_SERVICES']
    svcs = Yajl::Parser.parse(svcs)
    svcs.each do |svc|
      if svc["name"] =~ /^#{service_type}/
        opts = svc["options"]
        return opts
      end
    end
  end

  def db_name(service_type)
    opts = parse_env(service_type)
    opts["name"]
  end
end

put '/service/postgresql/dbeater/schema/:schema' do
  begin
    client = load_postgresql
    client.query("create schema #{params[:schema]};")
    params[:schema]
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    client.close
    params[:schema]
  end
end

put '/service/postgresql/dbeater/table/:table' do
  begin
  client = load_postgresql
  client.query("create table #{params[:table]} (value text);")
  params[:table]
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    client.close
    params[:table]
 end
end

put '/service/postgresql/dbeater/temptable/:table' do
  begin
  client = load_postgresql
  output=""
  db_size_1 = client.query("select pg_database_size('#{db_name("postgresql")}')").first['pg_database_size']
  output << "#{db_size_1} ... "
  client.query("create temp table #{params[:table]}_temp as select * from #{params[:table]}")
  client.transaction do |conn|
    res = conn.query("select count(*) as temp_count from #{params[:table]}_temp ")
    res.each do |x|
      output << "#{x} + "
    end
  end

  db_size_2 = client.query("select pg_database_size('#{db_name("postgresql")}')").first['pg_database_size']
  output << "#{db_size_2} ,,,"
  output << "++++"
  res = client.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';")
  res.each do |x|
    output << "#{x} - "
  end
  output << "--- "
  output
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
    client.close
 end
end


post '/service/postgresql/dbeater/:table/:mega' do
  c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
  # prepare 1M data
  content = (0..1000000).map{ c[rand(c.size)] }.join
  begin
  client = load_postgresql
  mega_no = params[:mega].to_i
  i = 1
  while i <= mega_no do
    client.query("insert into #{params[:table]} (value) values('#{content}');")
    i += 1
  end
  rescue => e
     "#{e} => #{e.backtrace}"
  ensure
    client.close
  end
end

get '/service/postgresql/dbeater/db/size' do
  begin
  client = load_postgresql
  db_size = client.query("select pg_database_size('#{db_name("postgresql")}')").first['pg_database_size']
  db_size
  rescue => e
    "#{e} => #{e.backtrace}"
  ensure
   client.close
  end
end


post '/service/postgresql/:key' do
  client = load_postgresql
  value = request.env["rack.input"].read
  result = client.query("select * from data_values where id = '#{params[:key]}';")
  if result.count > 0
    client.query("update data_values set data_value = '#{value}' where id = '#{params[:key]}';")
  else
    client.query("insert into data_values (id, data_value) values('#{params[:key]}','#{value}');")
  end
  client.close
  value
end

get '/service/postgresql/:key' do
  client = load_postgresql
  value = client.query("select data_value from  data_values where id = '#{params[:key]}'").first['data_value']
  client.close
  value
end

put '/service/postgresql/truncate/:table' do
  begin
    client = load_postgresql
    client.query("truncate table #{params[:table]};")
    client.close
    params[:table]
  rescue => e
     "#{e} => #{e.backtrace}"
  end
end

put '/service/postgresql/table/:table' do
  begin
  client = load_postgresql
  client.query("create table #{params[:table]} (x int);")
  client.close
  params[:table]
  rescue => e
     "#{e} => #{e.backtrace}"
  end
end

delete '/service/postgresql/:object/:name' do
  client = load_postgresql
  object = params[:object]
  name = params[:name]
  name += "()" if object=="function" # PG 'drop function' docs: "The argument types to the function must be specified"
  client.query("drop #{object} #{name};")
  client.close
  name
end

put '/service/postgresql/function/:function' do
  client = load_postgresql
  client.query("create function #{params[:function]}() returns integer as 'select 1234;' language sql;")
  client.close
  params[:function]
end

put '/service/postgresql/sequence/:sequence' do
  client = load_postgresql
  client.query("create sequence #{params[:sequence]};")
  client.close
  params[:sequence]
end

put '/service/rabbit/dbeater/table/:table' do
  params[:table]
end

post '/service/rabbit/dbeater/:table/:mega' do
  c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
  # prepare 1M data
  content = (0..1000000).map{ c[rand(c.size)] }.join
  begin
  client = rabbit_service
  mega_no = params[:mega].to_i
  i = 1
  while i <= mega_no do
    key = "#{params[:table]}_#{i}"
    write_to_rabbit(key, content, client)
    i += 1
  end
  rescue => e
     "#{e} => #{e.backtrace}"
  end
end

get '/service/rabbit/dbeater/db/size' do
  "unknown"
end

post '/service/rabbit/:key' do
  value = request.env["rack.input"].read
  client = rabbit_service
  write_to_rabbit(params[:key], value, client)
  value
end

get '/service/rabbit/:key' do
  client = rabbit_service
  read_from_rabbit(params[:key], client)
end

put '/service/rabbitmq/dbeater/table/:table' do
  params[:table]
end

post '/service/rabbitmq/dbeater/:table/:mega' do
    c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
  # prepare 1M data
  content = (0..1000000).map{ c[rand(c.size)] }.join
  begin
  client = rabbit_srs_service
  mega_no = params[:mega].to_i
  i = 1
  while i <= mega_no do
    key = "#{params[:table]}_#{i}"
    write_to_rabbit(key, content, client)
    i += 1
  end
  rescue => e
     "#{e} => #{e.backtrace}"
  end
end

get '/service/rabbitmq/dbeater/db/size' do
  "unknow"
end

post '/service/rabbitmq/:key' do
  value = request.env["rack.input"].read
  client = rabbit_srs_service
  write_to_rabbit(params[:key], value, client)
  value
end

get '/service/rabbitmq/:key' do
  client = rabbit_srs_service
  read_from_rabbit(params[:key], client)
end

put '/service/atmos/dbeater/table/:table' do
  params[:table]
end

post '/service/atmos/dbeater/:table/:mega' do
  begin
    client = load_atmos
    c = [('a'..'z'),('A'..'Z')].map{|i| Array(i)}.flatten
    # prepare 1M data
    content = (0..1000000).map{ c[rand(c.size)] }.join
    i = 1
    mega_no = params[:mega].to_i
    obj_ids = []
    while i <= mega_no do
      res = client.create_obj(content)
      obj_id = res['location']
      obj_ids << obj_id.to_s.gsub("#{ATMOS_OBJ_PREFIX}", '')
      i += 1
    end
    obj_ids.join(", ")
  rescue => e
    "#{e} => #{e.backtrace}"
  end
end

get '/service/atmos/dbeater/db/size' do
  'unknown'
end

post '/service/atmos/object' do
  begin
    client = load_atmos
    content = request.body.read
    res = client.create_obj(content)
    obj_id = res['location']
    obj_id.to_s.gsub("#{ATMOS_OBJ_PREFIX}", '')
  rescue => e
    "#{e} => #{e.backtrace}"
  end
end

get '/service/atmos/object/:obj_id' do
  begin
    client = load_atmos
    obj_id = params[:obj_id]
    res = client.get_obj("#{ATMOS_OBJ_PREFIX}#{obj_id}")
    res.body
  rescue => e
    "#{e} => #{e.backtrace}"
  end
end

def load_redis
  redis_service = load_service('redis')
  Redis.new({:host => redis_service["hostname"], :port => redis_service["port"], :password => redis_service["password"]})
end

def mysql_db_size(conn, dbname)
  result = conn.query(
    "SELECT table_schema 'name', SUM( data_length + index_length ) 'size'
     FROM information_schema.TABLES GROUP BY table_schema" )
  if result.count > 0
    #result
    size=0
    result.each do |r|
      if r["name"] == dbname
        size = r["size"]
      end
    end
    "#{size.to_i}"
  else
    "0"
  end
end

def load_mysql
  mysql_service = load_service('mysql')
  client = Mysql2::Client.new(:host => mysql_service['hostname'], :username => mysql_service['user'], :port => mysql_service['port'], :password => mysql_service['password'], :database => mysql_service['name'])
  result = client.query("SELECT table_name FROM information_schema.tables WHERE table_name = 'data_values'");
  client.query("Create table IF NOT EXISTS data_values ( id varchar(20), data_value varchar(20)); ") if result.count != 1
  client
end

def load_mongo
  mongodb_service = load_service('mongodb')
  conn = Mongo::Connection.new(mongodb_service['hostname'], mongodb_service['port'])
  db = conn[mongodb_service['db']]
  coll = db['data_values'] if db.authenticate(mongodb_service['username'], mongodb_service['password'])
  db
end

def load_postgresql
  postgresql_service = load_service('postgresql')
  client = PGconn.open(postgresql_service['host'], postgresql_service['port'], :dbname => postgresql_service['name'], :user => postgresql_service['username'], :password => postgresql_service['password'])
  client.query("create table data_values (id varchar(20), data_value varchar(20));") if client.query("select * from pg_catalog.pg_class where relname = 'data_values';").num_tuples() < 1
  client
end

def load_service(service_name)
  services = JSON.parse(ENV['VMC_SERVICES'])
  service = services.find {|service| service["vendor"].downcase == service_name}
  service = service["options"] if service
end

def rabbit_service
  service = load_service('rabbitmq')
  Carrot.new( :host => service['hostname'], :port => service['port'], :user => service['user'], :pass => service['pass'], :vhost => service['vhost'] )
end

def rabbit_srs_service
  service = load_service('rabbitmq')
  uri = URI.parse(service['url'])
  host = uri.host
  port = uri.port
  user = uri.user
  pass = uri.password
  vhost = uri.path[1..uri.path.length]
  Carrot.new( :host => host, :port => port, :user => user, :pass => pass, :vhost => vhost )
end

def write_to_rabbit(key, value, client)
  q = client.queue(key)
  q.publish(value)
end

def read_from_rabbit(key, client)
  q = client.queue(key)
  msg = q.pop(:ack => true)
  q.ack
  msg
end

def load_atmos
  atmos={}
  opts = load_service("atmos")
  atmos[:host] = opts["host"]
  atmos[:uid] = opts["token"]
  atmos[:sid] = opts["subtenant_id"]
  atmos[:key] = opts["shared_secret"]
  atmos[:port] = opts["port"]
  client = AtmosClient.new(atmos)
end
