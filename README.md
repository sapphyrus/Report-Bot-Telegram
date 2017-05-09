# Report-Bot-Telegram
Telegram Wrapper for vapor-report

### Preview:
![Preview](http://i.imgur.com/nlTT5AF.png)

### Installation:
* Ruby und NodeJS installieren (Gibts beides für Windows & Linux)
* Mit 'gem install mysql2 mysql2-cs-bind telegram-bot-ruby colorize steam-condenser overlook-csgo sqlite3' alle Abhängigkeiten vom Telegram-Bot installieren
* Den guten @BotFather auf Telegram anschreiben und mit /newbot einen neuen Bot erstellen. Den Token in die config.json eintragen
* Falls man den OW-Check verwenden möchte, muss ein Steam-API-Key in die config eingetragen werden. Diesen kriegt man hier. Dieser Schritt kann übersprungen werden.
* Bot.rb mit 'ruby bot.rb' starten. Dort sollte angezeigt werden, dass die NodeJS-Dependencies erfolgreich installiert wurden. Dann auf Telegram unter dem gewählten Namen anschreiben. Die angezeigte ChatID in users.txt schreiben.
* Alle Steam-Accounts im format 'username:password' in accounts.txt eintragen.
* Bot stoppen und starten.
