begin
  require 'mysql2'
  require 'mysql2-cs-bind'
  require 'telegram/bot'
  require 'colorize'
  require 'open-uri'
  require 'json'
  require 'openssl'
  require 'open3'
  require 'steam-condenser'
  require 'overlook'
  require 'sqlite3'
  require 'thwait'
rescue LoadError => e
  puts "MISSING DEPENDENCIES! (#{e.message})"
  puts "run 'gem install mysql2 mysql2-cs-bind telegram-bot-ruby colorize steam-condenser overlook-csgo sqlite3' to install them."
end

trap("INT") {
  exit
}

def utf8(string)
  return string.encode(Encoding.find('ASCII'), {:invalid => :replace, :undef => :replace, :replace => '', :universal_newline => true})
end

def log_timestamp
  time = Time.now.strftime("%d.%m.%Y %H:%M:%S")
  return "[#{time}]".black.on_white
end

def log(message)
  puts "#{log_timestamp}" + " " + message
end

$VERBOSE = nil
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

accounts = File.read('accounts.txt').split("\n")
users = File.read('users.txt').split("\n")
config = JSON.parse(File.read('config.json').split("\n").join(""))

log "Starting CSGO Telegram ReportBot by sapphyrus..."
log "We currently have #{accounts.length} account(s) and #{users.length} user(s)!"
log "Credits to luk1337, askwrite and seishun!"

if config['token'].empty?
  log "Telegram Token not set! Message @botfather to get one!".red
  exit
end

node_check, status = Open3.capture2e("node ./vapor-report/report.js")

if node_check.chomp == "Usage: node report.js [username] [password] [steamid]"
  log "vapor-report seems to be working!".green
elsif node_check.include? "Cannot find module"
  log "Installing vapor-report's dependencies..."
  install_dependencies = `cd vapor-report && npm install`
  node_check, status = Open3.capture2e("node ./vapor-report/report.js")
  if node_check.chomp == "Usage: node report.js [username] [password] [steamid]"
    log "Installation successful!"
  else
    puts install_dependencies.to_s
    log "Installation failed!"
    exit
  end
else
  log "NodeJS not installed!".red
  exit
end

$db = SQLite3::Database.new "reports.sqlite"
$db.execute "
  create table IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    steamid TEXT,
    nickname TEXT,
    reported_by TEXT,
    banned INT(1)
  );
"

Thread.abort_on_exception = true
if config["ow-check"]
  if config["steam-api-key"].empty?
    log "Steam API-Key not set! Can't start OW-Check".red
  else
    begin
      steamstatus = JSON.parse(open("https://api.steampowered.com/ICSGOServers_730/GetGameServersStatus/v1/?key=#{config['steam-api-key']}").read)["result"]
    rescue
      log "Invalid Steam API-Key!".red
    end
    if !steamstatus.nil?
      log "Steam API seems to be working!".green
      Thread.new do
        while true
          accounts = Array.new
          $db.execute("SELECT * FROM reports WHERE banned = 0 ORDER BY id LIMIT 100") do |row|
            accounts << [row[0], row[1], row[2], row[3], row[4]]
          end
          steamids = ""
          accounts.each do |account|
            steamids = steamids + "#{account[1]},"
          end
          steamids = steamids.chomp(",")
          result = JSON.parse(open("http://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=#{config['steam-api-key']}&steamids=#{steamids}").read)["players"]
          id = 0
          result.each do |bans|
            account = accounts[id]
            if bans["NumberOfGameBans"] >= 1
              $db.execute("UPDATE reports SET banned = 1 WHERE id = #{account[0]}")
              log "'#{account[1]}' has been banned. Notifying #{account[3]}"
              Telegram::Bot::Client.run(config['token']) do |bot| #TODO: Müsste besser gehen, ohne dass sich der Bot neu einloggen muss
                bot.api.send_message(chat_id: account[3].to_i, parse_mode: "Markdown", text: "[#{account[2]}](https://steamcommunity.com/profiles/#{account[1]}) has been OW banned!")
              end
            end
            id += 1
          end
          sleep 5
        end
      end
    end
  end
end

Telegram::Bot::Client.run(config['token']) do |bot|
  bot.listen do |message|
    begin
      if !message.text.nil?
        args = message.text.split(" ")
        is_user = users.include? message.chat.id.to_s
        log "New message from '" + message.chat.id.to_s + "' (is user: #{is_user}): " + args.inspect
        case args[0]
        when "/start"
          bot.api.send_message(chat_id: message.chat.id, text: "Welcome to #{config['name']}! Your ChatID is " + message.chat.id.to_s)
        when "/report"
          if is_user
            if args.length == 2 or args.length == 3
              steamid = args[1].gsub("https://", "").gsub("http://", "").gsub("steamcommunity.com/id/", "").gsub("steamcommunity.com/profiles/", "")
              if steamid.to_i.to_s == steamid
                steamid = steamid.to_i
              end
              begin
                steamid = SteamId.new steamid
              rescue SteamCondenserError
                bot.api.send_message(chat_id: message.chat.id, text: "Couldn't fetch profile. Check if the url/steamid is correct.")
                steamid = nil
              end
              if !steamid.nil?
                if args.length == 2
                  bot.api.send_message(chat_id: message.chat.id, parse_mode: "Markdown", text: "Reportbotting [#{steamid.steam_id64}](https://steamcommunity.com/profiles/#{steamid.steam_id64})!")
                else
                  matchid = Overlook.decode_share_code(args[2].gsub("steam://rungame/730/76561202255233023/+csgo_download_match%20", ""))
                  bot.api.send_message(chat_id: message.chat.id, parse_mode: "Markdown", text: "Reportbotting [#{steamid.steam_id64}](https://steamcommunity.com/profiles/#{steamid.steam_id64}) with matchid #{matchid[:matchid]}!")
                end
                `node ./vapor-report/protos/updater.js`
                threads = []
                accounts = File.read('accounts.txt').split("\n")
                accounts.each do | account |
                  account = account.split(":")
                  threads << Thread.new do
                    if args.length == 2
                      cmd = "node ./vapor-report/report.js #{account[0]} #{account[1]} #{steamid.steam_id64}"
                    else
                      cmd = "node ./vapor-report/report_matchid.js #{account[0]} #{account[1]} #{steamid.steam_id64} #{matchid[:matchid]}"
                    end
                    log("[#{account[0]}] running '" + utf8(cmd) + "'")
                    Open3.popen3(cmd) do |stdin, stdout, stderr, thread|
                      while !(raw_line = stdout.gets).nil?
                        log("[#{account[0]}] - " + utf8(raw_line))
                        bot.api.send_message(chat_id: message.chat.id, parse_mode: "Markdown", text: utf8("*[#{account[0]}]* - #{raw_line}")) unless raw_line.length <= 2
                      end
                    end
                    sleep 0.1
                  end
                end
                ThreadsWait.all_waits(*threads)
                bot.api.send_message(chat_id: message.chat.id, parse_mode: "Markdown", text: "#{threads.length.to_s} reports sent to [#{steamid.steam_id64}](https://steamcommunity.com/profiles/#{steamid.steam_id64})! You will receive a notification if he gets banned.")
                $db.execute("INSERT INTO reports (steamid, nickname, reported_by, banned) VALUES (?, ?, ?, ?)", [steamid.steam_id64.to_s, utf8(steamid.nickname.to_s), message.chat.id.to_s, 0])
              end
            else
              bot.api.send_message(chat_id: message.chat.id, text: "Usage: /report (SteamID/url)")
            end
          else
            bot.api.send_message(chat_id: message.chat.id, text: "You're not allowed to use this!")
          end
        when "/reports"
          text = "Latest reports (Limited to 15 entries):\n"
          $db.execute("SELECT * FROM reports ORDER BY id LIMIT 15") do |row|
            if config["ow-check"]
              banned = "no"
              banned = "yes" if row[4] == 1
              text = text + "#{row[0].to_s} - [#{row[2]}](https://steamcommunity.com/profiles/#{row[1]}) (banned: #{banned})\n"
            else
              text = text + "#{row[0].to_s} - [#{row[2]}](https://steamcommunity.com/profiles/#{row[1]})\n"
            end
          end
          bot.api.send_message(chat_id: message.chat.id, parse_mode: "Markdown", text: utf8(text))
        when "/bans"
          if config["ow-check"]
            text = "Latest bans (Limited to 15 entries):\n"
            $db.execute("SELECT * FROM reports WHERE banned = 1 ORDER BY id LIMIT 15") do |row|
              text = text + "#{row[0].to_s} - [#{row[2]}](https://steamcommunity.com/profiles/#{row[1]})\n"
            end
            bot.api.send_message(chat_id: message.chat.id, parse_mode: "Markdown", text: utf8(text))
          else
            bot.api.send_message(chat_id: message.chat.id, text: "Enable the OW-Check to use this command!")
          end
        else
          bot.api.send_message(chat_id: message.chat.id, text: "Unknown command.")
        end
      end
      rescue StandardError => e
        log "Error occurred while handeling message: '" + message.text + "'" + ": " + e.message
    end
  end
end
