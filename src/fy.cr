require "kemal"
require "kemal-mysql"
require "session"
require "base64"
require "uri"
require "json"
require "secure_random"

CONN_OPTS = {
  "host" => "127.0.0.1",
  "user" => "fy",
  "password" => "fy",
  "db" => "fy"
}

# TODO
# If a node loses all its children, it should not be marked
# as a parent anymore.
#

mysql_connect CONN_OPTS

add_handler Session::Handler(Hash(String, String)).new(secret: "besecret")

# I really hope I find a way to perform prepared inserts
# rather than this ugly dance.
class String
  def sanitize
    to_s.gsub(/\\/, "\&\&").gsub(/'/, "''")
  end
end

macro query(template, params={} of Symbol => MySQL::Types::SqlType)
  MySQL::Query.new({{template}}, {{params}}).run(conn)
end

macro body_param(name)
  URI.unescape(env.params.body[{{name}}] as String, true)
end

macro reply_json(data, diag = 200)
  env.response.content_type = "application/json"
  env.response.status_code = {{diag}}
  {{data}}.to_json
end

# top level: parent == ""
def get_level_entries_deferred_release(env, parent_id, use_parent)
  r = query(%{SELECT id FROM maps WHERE nid=:parent_id}, {"parent_id" => parent_id})
  if r.not_nil!.size == 1
    s_parent = r.not_nil![0][0] as String
  else
    s_parent = ""
  end
  release
  if use_parent
    query(%{SELECT nid, content, sortorder, children, task, checked FROM entries LEFT JOIN maps ON entries.id=maps.id WHERE parent=:parent ORDER BY sortorder},
        {"parent" => s_parent})
  else
    query(%{SELECT nid, content, sortorder, children, task, checked FROM entries LEFT JOIN maps ON entries.id=maps.id WHERE entries.id=:parent ORDER BY sortorder},
        {"parent" => s_parent})
  end
end

def get_entry_id(env, nid)
  return "" if nid == "0"
  r = query(%{SELECT id FROM maps WHERE nid=:nid}, {"nid" => nid}).not_nil![0][0]
  release
  r
end

def get_entry_id_and_child_idx(env, nid : String)
  if nid == "0"
    r = query(%{SELECT '',MAX(sortorder) AS max_sort FROM entries WHERE parent=''}).not_nil![0]
  else
    r = query(%{SELECT maps.id,MAX(sortorder) AS max_sort FROM maps LEFT JOIN entries ON maps.id=entries.parent WHERE nid=:nid},
        {"nid" => nid}).not_nil![0]
  end
  release
  r
end

def get_entry_nid(env, id : String)
  r = query(%{SELECT nid FROM maps WHERE id=:id}, {"id" => id}).not_nil![0][0]
  release
  r
end

def insert_entry(env, parent : Nil | String, content : String, sortorder : Int32)
  uuid = SecureRandom.uuid
  query(%{INSERT INTO entries(id, parent, content, sortorder) VALUES(:id, :parent, :content, :sortorder)},
    {"id" => uuid, "parent" => parent, "content" => content, "sortorder" => sortorder})
  release
  query(%{INSERT INTO maps(id) VALUES(:uuid)}, {"uuid" => uuid})
  release
  if parent != nil
    query(%{UPDATE entries SET children = children + 1 WHERE id = :parent}, {"parent" => parent})
    release
  end
  uuid
end

def update_entry_checkedness(env, id : String, check : String)
  checkedness = check == "true" ? 1 : 0
  query(%{UPDATE entries SET checked=:checkedness WHERE id=:id}, {"checkedness" => checkedness, "id" => id})
  release
end

def update_entry_taskness(env, id : String, task : String)
  taskness = task == "true" ? 1 : 0
  query(%{UPDATE entries SET task=:taskness WHERE id=:id}, {"taskness" => taskness, "id" => id})
  release
end

def update_entry_content(env, id : String, content : String)
  query(%{UPDATE entries SET content=:content WHERE id=:id}, {"content" => content, "id" => id})
  release
end

def delete_entry_by_id(env, id : String)
  query(%{DELETE FROM entries WHERE id=:id}, {"id" => id})
  release
  query(%{DELETE FROM maps WHERE id=:id}, {"id" => id})
  release
end

def swap_entry_position(env, tid : String, id : String)
  positions = query(%{SELECT sortorder FROM entries WHERE id IN (:id, :tid) ORDER BY sortorder},
    {"id" => id, "tid" => tid}).not_nil!
  release
  query(%{UPDATE entries SET sortorder=:position WHERE id=:id},
    {"position" => positions[1][0], "id" => id})
  release
  query(%{UPDATE entries SET sortorder=:position WHERE id=:id},
    {"position" => positions[0][0], "id" => tid})
  release
end

def move_after_position(env, tid : String, id : String)
  # We now need to proceed with two sets of updates:
  # 1. insert node after parent; increment remaining siblings
  # 2. parent's children after our original position: decrement siblings
  parent_position, grandad = query(%{SELECT sortorder, parent FROM entries WHERE id=:id},
    {"id" => tid}).not_nil![0]
  release
  node_position  = query(%{SELECT sortorder FROM entries WHERE id=:id},
    {"id" => id}).not_nil![0][0]
  release
  query(%{UPDATE entries SET sortorder=sortorder+1 WHERE parent=:parent AND sortorder > :position},
    {"parent" => grandad, "position" => parent_position})
  release
  query(%{UPDATE entries SET sortorder=sortorder-1 WHERE parent=:id AND sortorder > :position},
    {"id" => tid, "position" => node_position})
  release
  query(%{UPDATE entries SET sortorder=:position+1, parent=:parent WHERE id=:id},
    {"position" => parent_position, "parent" => grandad, "id" => id})
  release
  puts "#{id} -> #{tid} -> #{grandad}"
  puts "#{node_position} -> #{parent_position}"
end

def to_sha1_str(source : String, salt : String)
  shad = OpenSSL::SHA1.hash(salt + source)
  Base64.encode String.build do |str|
    shad.each do |b|
      str << b.chr
    end
  end
end

def attempt_log_in(env, password, user)
  if user[1] == to_sha1_str(password as String, user[2] as String)
    log_in(env, user[0] as String, user[3] as Bool)
    true
  else
    false
  end
end

def log_in(env, username, admin)
  env.session["logged_in"] = "true"
  env.session["username"] = username
  env.session["admin"]    = admin ? "true" : "false"
end

def log_out(env)
  env.session["logged_in"] = "false"
end

def get_user_by_name(env, username : String)
  r = query(%{SELECT username, password, salt, admin FROM users WHERE username=:username},
    {"username" => username}).not_nil!
  release
  r.size > 0 ? r[0] : nil
end

def create_user(env, username : String, password : String)
  s_username = username.sanitize
  s_password = password.sanitize
  salt = SecureRandom.uuid.sanitize
  enc_password = to_sha1_str(s_password, salt)
  query(%{INSERT INTO users(username, password, salt) VALUES(:username, :password, :salt)},
    {"username" => username, "password" => enc_password, "salt" => salt})
  release
  log_in(env, s_username, false)
end

def populate_test_data(env)
  conn.query(%(DROP TABLE IF EXISTS users))
  release
  conn.query(%(DROP TABLE IF EXISTS maps))
  release
  conn.query(%(DROP TABLE IF EXISTS entries))
  release
  conn.query(%(CREATE TABLE entries(id VARCHAR(48) NOT NULL, parent VARCHAR(48) NOT NULL, content TEXT, sortorder INT, children INT DEFAULT 0, task TINYINT(1) DEFAULT 0, checked TINYINT(1) DEFAULT 0, PRIMARY KEY(id))))
  release
  conn.query(%(CREATE TABLE maps(nid INT NOT NULL AUTO_INCREMENT, id VARCHAR(48), primary KEY(nid))))
  release
  conn.query(%(CREATE TABLE users(uid INT NOT NULL AUTO_INCREMENT, username VARCHAR(64) NOT NULL, password VARCHAR(128) NOT NULL, salt VARCHAR(64) NOT NULL, admin TINYINT(1) DEFAULT 0, PRIMARY KEY(uid))))
  release

  uuid = insert_entry(env, nil, "This is a top level entry", 1)
  uuid = insert_entry(env, nil, "This is another top level entry", 2)
  uuid = insert_entry(env, uuid, "This is child entry", 1)
end

def get_login_text(env)
  if env.session["logged_in"] == "false"
    %(<a href="/login">login</a>)
  else
    %(Hello, #{env.session["username"]}#{(env.session["admin"]=="true" ? "/admin" : "")} (<a href="/logout">logout</a>))
  end
end

def get_username_text(env)
  if env.session["logged_in"] == "false"
    "guest"
  else
    %(#{env.session["username"]}#{(env.session["admin"]=="true" ? "/admin" : "")})
  end
end

def get_action_text(env)
  if env.session["logged_in"] == "false"
    %(<a href="/login">login</a>)
  else
    %(<a href="/logout">logout</a>)
  end
end

def is_logged_in(env)
  env.session["logged_in"] == "true"
end

def is_admin(env)
  is_logged_in(env) && env.session["admin"] == "true"
end

def before_this(env)
  env.session["session_started_at"] ||= Time.now.to_s
  env.session["logged_in"] ||= "false"
end

get "/" do |env|
  before_this env

  if env.session["logged_in"] == "false"
    env.redirect "/login"
  else
    login_or_logout = get_login_text env
    username = get_username_text env
    log_action = get_action_text env
    render "src/views/index.ecr", "src/views/layout.ecr"
  end
end

get "/login" do |env|
  render "src/views/login.ecr"
end

post "/login" do |env|
  before_this env

  if body_param("username") == "" || body_param("password") == ""
    render "src/views/login.ecr"
  else
    user = get_user_by_name(env, body_param("username"))
    if user == nil
      create_user(env, body_param("username"), body_param("password"))
      env.redirect "/"
    else
      if attempt_log_in(env, body_param("password"), user.not_nil!)
        env.redirect "/"
      else
        render "src/views/login.ecr"
      end
    end
  end
end

get "/logout" do |env|
  log_out env
  env.redirect "/login"
end

post "/checktask.json" do |env|
  before_this env

  id = get_entry_id(env, body_param("id"))
  update_entry_checkedness(env, id as String, body_param("checked"))
end

post "/maketask.json" do |env|
  before_this env

  id = get_entry_id(env, body_param("id"))
  update_entry_taskness(env, id as String, body_param("task"))
end

post "/rename.json" do |env|
  before_this env

  id = get_entry_id(env, body_param("id"))
  update_entry_content(env, id as String, URI.unescape(body_param("content")))
end

post "/remove.json" do |env|
  before_this env

  id = get_entry_id(env, body_param("id"))
  delete_entry_by_id(env, id as String)
end

post "/add.json" do |env|
  before_this env

  pid = env.params.body.has_key?("pid") ? body_param("pid") : "0"
  uuid, child_idx = get_entry_id_and_child_idx(env, pid as String)
  child_idx = 0 if child_idx == nil
  # when adding a child, it is added at the bottom of its
  # parent's children list, so we need to retrieve that
  # and use it.
  uuid = insert_entry(env, uuid as String, body_param("content"), child_idx.not_nil!.to_s.to_i + 1)
  nid = get_entry_nid(env, uuid)
  reply_json({add: "ok", id: nid.to_s})
end

post "/moveprev.json" do |env|
  before_this env

  tuid = get_entry_id(env, body_param("tid")) as String
  uuid = get_entry_id(env, body_param("id")) as String
  swap_entry_position(env, uuid, tuid)
  reply_json({moveprev: "ok"})
end

post "/movenext.json" do |env|
  before_this env

  tuid = get_entry_id(env, body_param("tid")) as String
  uuid = get_entry_id(env, body_param("id")) as String
  swap_entry_position(env, tuid, uuid)
  reply_json({movenext: "ok"})
end

post "/moveafter.json" do |env|
  before_this env

  tuid = get_entry_id(env, body_param("tid")) as String
  uuid = get_entry_id(env, body_param("id")) as String
  move_after_position(env, tuid, uuid)
  reply_json({moveafter: "ok"})
end

post "/entries.json" do |env|
  before_this env

  # If we have an empty document so far
  ppid = env.params.body.has_key?("id")  ? body_param("id").not_nil!.to_s.to_i : 0
  if env.params.body.has_key?("queryContext") && body_param("queryContext") != "0" && ppid == 0
    pid = body_param("queryContext")
    use_parent = false
  else
    pid = ppid
    use_parent = true
  end
  reply = [] of Hash(Symbol, String | Bool)

  get_level_entries_deferred_release(env, pid, use_parent).not_nil!.each do |entry|
    reply << {id: entry[0].to_s, name: String.new(entry[1] as Slice(UInt8)), isParent: entry[3] as Int32 > 0, drag: true, drop: true, task:(entry[4] == true ? true : false), checked:(entry[5] == true ? true : false)}
  end
  release

  reply_json(reply)
end

# For initialization when empty:
get "/reset" do |env|
  before_this env

  if is_admin env
    populate_test_data env
  else
    "Good try, buddy."
  end
end

Kemal.run
