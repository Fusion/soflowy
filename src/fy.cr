require "kemal"
require "kemal-mysql"
require "session"
require "base64"
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


def reply_json(env, data, diag = 200)
  env.response.content_type = "application/json"
  env.response.status_code = diag
  data.to_json
end

# top level: parent == ""
def get_level_entries_deferred_release(env, parent_id)
  r = conn.query(%(SELECT id FROM maps WHERE nid='#{parent_id}'))
  if r.not_nil!.size == 1
    s_parent = (r.not_nil![0][0] as String).sanitize
  else
    s_parent = ""
  end
  release
  conn.query(%(SELECT nid, content, sortorder, children FROM entries LEFT JOIN maps ON entries.id=maps.id WHERE parent="#{s_parent}" ORDER BY sortorder))
end

def get_entry_id(env, nid)
  r = conn.query(%(SELECT id FROM maps WHERE nid='#{nid}')).not_nil![0][0]
  release
  r
end

def get_entry_id_and_child_idx(env, nid : String)
  s_nid = nid.sanitize
  r = conn.query(%(SELECT maps.id,MAX(sortorder) AS max_sort FROM maps LEFT JOIN entries ON maps.id=entries.parent WHERE nid='#{s_nid}')).not_nil![0]
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

def update_entry(env, id : String, content : String)
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
  conn.query(%(CREATE TABLE entries(id VARCHAR(48) NOT NULL, parent VARCHAR(48) NOT NULL, content TEXT, sortorder INT, children INT DEFAULT 0, PRIMARY KEY(id))))
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

  if env.params["username"] == "" || env.params["password"] == ""
    render "src/views/login.ecr"
  else
    user = get_user_by_name(env, env.params["username"] as String) 
    if user == nil
      create_user(env, env.params["username"] as String, env.params["password"] as String)
      env.redirect "/"
    else
      if attempt_log_in(env, env.params["password"], user.not_nil!)
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

get "/rename.json" do |env|
  before_this env

  id = get_entry_id(env, env.params["id"] as String)
  update_entry(env, id as String, env.params["content"] as String)
end

get "/remove.json" do |env|
  before_this env

  id = get_entry_id(env, env.params["id"] as String)
  delete_entry_by_id(env, id as String)
end

get "/add.json" do |env|
  before_this env

  uuid, child_idx = get_entry_id_and_child_idx(env, env.params["pid"] as String)
  child_idx = 0 if child_idx == nil
  # when adding a child, it is added at the bottom of its
  # parent's children list, so we need to retrieve that
  # and use it.
  uuid = insert_entry(env, uuid as String, env.params["content"] as String, child_idx.not_nil!.to_s.to_i + 1)
  nid = get_entry_nid(env, uuid)
  reply_json(env, {add: "ok", id: nid.to_s})
end

post "/entries.json" do |env|
  before_this env

  # If we have an empty document so far
  pid = env.params["queryParent"] != "0" ? env.params["queryParent"] : env.params.has_key?("id")  ? env.params["id"].not_nil!.to_s.to_i : 0
  reply = [] of Hash(Symbol, String | Bool)

  get_level_entries_deferred_release(env, pid).not_nil!.each do |entry|
    reply << {id: entry[0].to_s, name: entry[1] as String, isParent: entry[3] as Int32 > 0}
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
