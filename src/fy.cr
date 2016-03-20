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

mysql_connect CONN_OPTS

add_handler Session::Handler(Hash(String, String)).new(secret: "besecret")

# I really hope I find a way to perform prepared inserts
# rather than this ugly dance.
class String
  def sanitize
    to_s.gsub(/\\/, "\&\&").gsub(/'/, "''")
  end
end


def body_param(env, name)
  URI.unescape(env.params.body[name] as String, true)
end

def reply_json(env, data, diag = 200)
  env.response.content_type = "application/json"
  env.response.status_code = diag
  data.to_json
end

# top level: parent == ""
def get_level_entries_deferred_release(env, parent_id, use_parent)
  r = conn.query(%(SELECT id FROM maps WHERE nid='#{parent_id}'))
  if r.not_nil!.size == 1
    s_parent = (r.not_nil![0][0] as String).sanitize
  else
    s_parent = ""
  end
  release
  if use_parent
    conn.query(%(SELECT nid, content, sortorder, children, task, checked FROM entries LEFT JOIN maps ON entries.id=maps.id WHERE parent="#{s_parent}" ORDER BY sortorder))
  else
    conn.query(%(SELECT nid, content, sortorder, children, task, checked FROM entries LEFT JOIN maps ON entries.id=maps.id WHERE entries.id="#{s_parent}" ORDER BY sortorder))
  end
end

def get_entry_id(env, nid)
  s_nid = nid.sanitize
  return "" if s_nid == "0"
  r = conn.query(%(SELECT id FROM maps WHERE nid='#{s_nid}')).not_nil![0][0]
  release
  r
end

def get_entry_id_and_child_idx(env, nid : String)
  s_nid = nid.sanitize
  if s_nid == "0"
    r = conn.query(%(SELECT '',MAX(sortorder) AS max_sort FROM entries WHERE parent='')).not_nil![0]
  else
    r = conn.query(%(SELECT maps.id,MAX(sortorder) AS max_sort FROM maps LEFT JOIN entries ON maps.id=entries.parent WHERE nid='#{s_nid}')).not_nil![0]
  end
  release
  r
end

def get_entry_nid(env, id : String)
  s_id = id.sanitize
  r = conn.query(%(SELECT nid FROM maps WHERE id='#{s_id}')).not_nil![0][0]
  release
  r
end

def insert_entry(env, parent : Nil | String, content : String, sortorder : Int32)
  uuid = SecureRandom.uuid
  s_parent = parent == nil ? nil : parent.not_nil!.sanitize
  s_content = content.sanitize
  conn.query(%(INSERT INTO entries(id, parent, content, sortorder) VALUES("#{uuid}", "#{s_parent}", "#{s_content}", #{sortorder})))
  release
  conn.query(%(INSERT INTO maps(id) VALUES("#{uuid}")))
  release
  if parent != nil
    conn.query(%(UPDATE entries SET children = children + 1 WHERE id = "#{s_parent}"))
    release
  end
  uuid
end

def update_entry_checkedness(env, id : String, check : String)
  s_id = id.sanitize
  checkedness = check == "true" ? 1 : 0
  conn.query(%(UPDATE entries SET checked=#{checkedness} WHERE id="#{s_id}"))
  release
end

def update_entry_taskness(env, id : String, task : String)
  s_id = id.sanitize
  taskness = task == "true" ? 1 : 0
  conn.query(%(UPDATE entries SET task=#{taskness} WHERE id="#{s_id}"))
  release
end

def update_entry_content(env, id : String, content : String)
  s_id = id.sanitize
  conn.query(%(UPDATE entries SET content="#{content}" WHERE id="#{s_id}"))
  release
end

def delete_entry_by_id(env, id : String)
  s_id = id.sanitize
  conn.query(%(DELETE FROM entries WHERE id="#{s_id}"))
  release
  conn.query(%(DELETE FROM maps WHERE id="#{s_id}"))
  release
end

def swap_entry_position(env, tid : String, id : String)
  s_tid = tid.sanitize
  s_id  = id.sanitize
  positions = conn.query(%(SELECT sortorder FROM entries WHERE id IN ("#{s_id}", "#{s_tid}") ORDER BY sortorder)).not_nil!
  release
  conn.query(%(UPDATE entries SET sortorder=#{positions[1][0]} WHERE id="#{s_id}"))
  release
  conn.query(%(UPDATE entries SET sortorder=#{positions[0][0]} WHERE id="#{s_tid}"))
  release
end

def move_after_position(env, tid : String, id : String)
  s_tid = tid.sanitize
  s_id  = id.sanitize
  # We now need to proceed with two sets of updates:
  # 1. insert node after parent; increment remaining siblings
  # 2. parent's children after our original position: decrement siblings
  parent_position, grandad = conn.query(%(SELECT sortorder, parent FROM entries WHERE id="#{s_tid}")).not_nil![0]
  release
  node_position  = conn.query(%(SELECT sortorder FROM entries WHERE id="#{s_id}")).not_nil![0][0]
  release
  conn.query(%(UPDATE entries SET sortorder=sortorder+1 WHERE parent="#{grandad}" AND sortorder > #{parent_position}))
  release
  conn.query(%(UPDATE entries SET sortorder=sortorder-1 WHERE parent="#{s_tid}" AND sortorder > #{node_position}))
  release
  conn.query(%(UPDATE entries SET sortorder=#{parent_position}+1, parent="#{grandad}" WHERE id="#{s_id}"))
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
  s_username = username.sanitize
  r = conn.query(%(SELECT username, password, salt, admin FROM users WHERE username="#{s_username}")).not_nil!
  release
  r.size > 0 ? r[0] : nil
end

def create_user(env, username : String, password : String)
  s_username = username.sanitize
  s_password = password.sanitize
  salt = SecureRandom.uuid.sanitize
  enc_password = to_sha1_str(s_password, salt)
  conn.query(%(INSERT INTO users(username, password, salt) VALUES("#{s_username}", "#{enc_password}", "#{salt}")))
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

  if body_param(env, "username") == "" || body_param(env, "password") == ""
    render "src/views/login.ecr"
  else
    user = get_user_by_name(env, body_param(env, "username"))
    if user == nil
      create_user(env, body_param(env, "username"), body_param(env, "password"))
      env.redirect "/"
    else
      if attempt_log_in(env, body_param(env, "password"), user.not_nil!)
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

  id = get_entry_id(env, body_param(env, "id"))
  update_entry_checkedness(env, id as String, body_param(env, "checked"))
end

post "/maketask.json" do |env|
  before_this env

  id = get_entry_id(env, body_param(env, "id"))
  update_entry_taskness(env, id as String, body_param(env, "task"))
end

post "/rename.json" do |env|
  before_this env

  id = get_entry_id(env, body_param(env, "id"))
  update_entry_content(env, id as String, URI.unescape(body_param(env, "content")))
end

post "/remove.json" do |env|
  before_this env

  id = get_entry_id(env, body_param(env, "id"))
  delete_entry_by_id(env, id as String)
end

post "/add.json" do |env|
  before_this env

  pid = env.params.body.has_key?("pid") ? body_param(env, "pid") : "0"
  uuid, child_idx = get_entry_id_and_child_idx(env, pid as String)
  child_idx = 0 if child_idx == nil
  # when adding a child, it is added at the bottom of its
  # parent's children list, so we need to retrieve that
  # and use it.
  uuid = insert_entry(env, uuid as String, body_param(env, "content"), child_idx.not_nil!.to_s.to_i + 1)
  nid = get_entry_nid(env, uuid)
  reply_json(env, {add: "ok", id: nid.to_s})
end

post "/moveprev.json" do |env|
  before_this env

  tuid = get_entry_id(env, body_param(env, "tid")) as String
  uuid = get_entry_id(env, body_param(env, "id")) as String
  swap_entry_position(env, uuid, tuid)
  reply_json(env, {moveprev: "ok"})
end

post "/movenext.json" do |env|
  before_this env

  tuid = get_entry_id(env, body_param(env, "tid")) as String
  uuid = get_entry_id(env, body_param(env, "id")) as String
  swap_entry_position(env, tuid, uuid)
  reply_json(env, {movenext: "ok"})
end

post "/moveafter.json" do |env|
  before_this env

  tuid = get_entry_id(env, body_param(env, "tid")) as String
  uuid = get_entry_id(env, body_param(env, "id")) as String
  move_after_position(env, tuid, uuid)
  reply_json(env, {moveafter: "ok"})
end

post "/entries.json" do |env|
  before_this env

  # If we have an empty document so far
  ppid = env.params.body.has_key?("id")  ? body_param(env, "id").not_nil!.to_s.to_i : 0
  if env.params.body.has_key?("queryContext") && body_param(env, "queryContext") != "0" && ppid == 0
    pid = body_param(env, "queryContext")
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

  reply_json(env, reply)
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
