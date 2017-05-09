var vapor = require('vapor');
var steamID = require("steamid");
var protos = require("./protos/protos.js");

if (!process.argv[4]) {
    console.log("Usage: node report.js [username] [password] [steamid]");
    process.exit();
}

var config = {
    "username": process.argv[2],
    "password": process.argv[3],
    "state": "Online"
};
var bot = vapor();
bot.init(config);

// Proto stuff
var ClientHello = 4006;
var ClientWelcome = 4004;

var clientTimeout = null;
var helloMsgInterval = null;

function stop(msg) {
    if (msg)
        console.log(msg);

    clearTimeout(clientTimeout);
    clearInterval(helloMsgInterval);

    bot.disconnect();
}

// Create custom plugin
bot.use({
    name: 'vapor-report',
    plugin: function(VaporAPI) {

        var Steam = VaporAPI.getSteam();
        var client = VaporAPI.getClient();
        var steamUser = VaporAPI.getHandler('steamUser');
        var steamGameCoordinator = new Steam.SteamGameCoordinator(client, 730);
        var clientMessage = {
            games_played: [{
                game_id: 730
            }]
        };


        VaporAPI.registerHandler({
            emitter: 'vapor',
            event: 'ready'
        }, function() {
            steamUser.gamesPlayed(clientMessage);

            helloMsgInterval = setInterval(function() {
                if (!client.connected)
                    return;

                if (steamGameCoordinator._client._connection == undefined)
                    stop("ERROR: Account is being used.");

                steamGameCoordinator.send({
                    msg: ClientHello,
                    proto: {}
                }, new protos.CMsgClientHello({}).toBuffer());
            }, 2000);

            clientTimeout = setTimeout(function() {
                stop("ERROR: Timed out after 15 seconds. This could mean that the account doesn't have csgo or is on report cooldown.");
            }, 15000);
        });



        VaporAPI.registerHandler({
            emitter: 'vapor',
            event: 'disconnected'
        }, function(error) {
            console.log('ERROR: ' + error.message);
            clearTimeout(clientTimeout);
            clearInterval(helloMsgInterval);
        });

        VaporAPI.registerHandler({
            emitter: 'vapor',
            event: 'steamGuard'
        }, function(callback) {
            stop('ERROR: Steam Guard not supported');
        });

        steamGameCoordinator.on('message', function(header, buffer, callback) {
            switch (header.msg) {
                case ClientWelcome:
                    clearInterval(helloMsgInterval);
                    steamGameCoordinator.send({
                        msg: protos.ECsgoGCMsg.k_EMsgGCCStrike15_v2_ClientReportPlayer,
                        proto: {}
                    }, new protos.CMsgGCCStrike15_v2_ClientReportPlayer({
                        accountId: new steamID(process.argv[4]).accountid,
                        matchId: 8,
                        rptAimbot: 2,
                        rptWallhack: 3,
                        rptSpeedhack: 4,
                        rptTeamharm: 5,
                        rptTextabuse: 6,
                        rptVoiceabuse: 7
                    }).toBuffer());
                    break;
                case protos.ECsgoGCMsg.k_EMsgGCCStrike15_v2_ClientReportResponse:
                    stop("Report with confirmation ID: " + protos.CMsgGCCStrike15_v2_ClientReportResponse.decode(buffer).confirmationId.toString() + " sent!");
                    break;
                default:
                    break;
            }
        });
    }
});

// Start the bot
bot.connect();

// Handle SIGINT (Ctrl+C) gracefully
process.on('SIGINT', function() {
    bot.disconnect();
    setTimeout(process.exit, 1000, 0);
});