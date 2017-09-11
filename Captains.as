#include "Logging.as";
#include "RulesCore.as";

const int TEAM_BLUE = 0;
const int TEAM_RED  = 1;

const SColor COLOR_BLUE(0xff0000ff);
const SColor COLOR_RED(0xffff0000);

void onInit(CRules@ this) {
    CaptainsReset(this);
}

void onRestart(CRules@ this) {
    CaptainsReset(this);
}

void onTick(CRules@ this) {
    /*
    log("onTick", "pick phase: " + this.get_bool("pick phase") + 
            ", team picking: " + this.get_u8("team picking"));
    */
    if (this.get_bool("pick phase")) {
        if (getPlayerCount() == 0 || CountPlayersInTeam(this.getSpectatorTeamNum()) == 0) {
            ExitPickPhase(this);
        }
        else {
            // Set the team that's picking
            int teamPicking;
            int blueCount = CountPlayersInTeam(TEAM_BLUE);
            int redCount = CountPlayersInTeam(TEAM_RED);

            if (blueCount == redCount) {
                teamPicking = this.get_u8("first pick");
            }
            else {
                teamPicking = blueCount < redCount ? TEAM_BLUE : TEAM_RED;
            }

            //log("onTick", "Set team picking to " + teamPicking);
            this.set_u8("team picking", teamPicking);
            this.Sync("team picking", true);
        }
    }
}

void onRender(CRules@ this) {
    if (this.get_bool("pick phase") && this.exists("team picking")) {
        // Draw interface
        u8 teamPicking = this.get_u8("team picking");

        Vec2f topLeft(8,200);
        Vec2f padding(4, 4);
        Vec2f endPadding(6, 0);
        string msg = (teamPicking == TEAM_BLUE ? "Blue" : "Red") + " team is picking";
        Vec2f textDims;
        GUI::SetFont("menu");
        GUI::GetTextDimensions(msg, textDims);
        GUI::DrawPane(topLeft, topLeft + textDims + padding*2 + endPadding);
        GUI::DrawText(msg, topLeft+padding, teamPicking == TEAM_BLUE ? COLOR_BLUE : COLOR_RED);
    }
}

void onNewPlayerJoin(CRules@ this, CPlayer@ player) {
    this.Sync("pick phase", true);
    this.Sync("team picking", true);
}

bool onServerProcessChat(CRules@ this, const string &in textIn, string &out textOut, CPlayer@ player) {
    // Handle !captains and !pick commands
    string[]@ tokens = textIn.split(" ");
    int tl = tokens.length;
    //log("onServerProcessChat", "called");

    if (tl > 0) {
       // log("onServerProcessChat", "tl > 0");
        if ((tokens[0] == "!captains") && tl >= 3) {
            //log("onServerProcessChat", "tokens[0]");
            CPlayer@ captain_blue = GetPlayerByIdent(tokens[1]);
            CPlayer@ captain_red  = GetPlayerByIdent(tokens[2]);
            if (captain_blue is null || captain_red is null) {
                log("onServerProcessChat", "One of the given captain names was invalid.");
            }
            else {
                //log("onServerProcessChat", "else");
                ForceAllToSpectate(this);
                SetBlueCaptain(this, captain_blue);
                SetRedCaptain(this, captain_red);
                StartPickPhase(this);
            }
        }
        else if (tokens[0] == "!pick" && tl >= 2 && this.get_bool("pick phase")) {
            u8 teamPicking = this.get_u8("team picking");
            CPlayer@ captain_blue = getPlayerByUsername(this.get_string("captain blue"));
            CPlayer@ captain_red  = getPlayerByUsername(this.get_string("captain red"));

            if (captain_blue is null || captain_red is null) {
                logBroadcast("onServerProcessChat", 
                        "ERROR: in pick phase but a captain is null; exiting pick phase.");
                ExitPickPhase(this);
            }
            else if (player is captain_blue && teamPicking == TEAM_BLUE ||
                        player is captain_red && teamPicking == TEAM_RED) {
                string targetIdent = tokens[1];
                CPlayer@ target = GetPlayerByIdent(targetIdent);
                if (target !is null) {
                    TryPickPlayer(this, target, player.getTeamNum());
                }
            }
        }
        else if (tokens[0] == "!allspec") {
            if (player.isMod() || IsPlayerCaptain(player))
                ForceAllToSpectate(this);
            else 
                getNet().server_SendMsg("Only a captain or mod can use that command.");

        }
        else if (tokens[0] == "!nextmap") {
            if (player.isMod() || IsPlayerCaptain(player))
                LoadNextMap();
            else
                getNet().server_SendMsg("Only a captain or mod can use that command.");
        }
    }

    return true;
}

void CaptainsReset(CRules@ this) {
    this.set_bool("pick phase", false);
    this.set_string("captain blue", "");
    this.set_string("captain red", "");
    this.set_u8("team picking", TEAM_BLUE);
    this.set_u8("first pick", TEAM_BLUE);
}

int CountPlayersInTeam(int teamNum) {
    int count = 0;

    for (int i=0; i < getPlayerCount(); i++) {
        CPlayer@ p = getPlayer(i);
        if (p is null) continue;

        if (p.getTeamNum() == teamNum)
            count++;
    }

    return count;
}

bool IsPlayerCaptain(CPlayer@ player) {
    if (player is null) {
        return false;
    }
    else {
        return player.getUsername() == getRules().get_string("captain blue") || player.getUsername() == getRules().get_string("captain red");
    }
}

CPlayer@ GetPlayerByIdent(string ident) {
    // Takes an identifier, which is a prefix of the player's character name
    // or username. If there is 1 matching player then they are returned.
    // If 0 or 2+ then a warning is logged.
    ident = ident.toLower();
    //log("GetPlayerByIdent", "ident = " + ident);
    CPlayer@[] matches; // players matching ident

    for (int i=0; i < getPlayerCount(); i++) {
        CPlayer@ p = getPlayer(i);
        if (p is null) continue;

        string username = p.getUsername().toLower();
        string charname = p.getCharacterName().toLower();

        if (username == ident || charname == ident) {
            //log("GetPlayerByIdent", "exact match found: " + p.getUsername());
            return p;
        }
        else if (username.find(ident) >= 0 || charname.find(ident) >= 0) {
            matches.push_back(p);
        }
    }

    if (matches.length == 1) {
        //log("GetPlayerByIdent", "1 match found: " + matches[0].getUsername());
        return matches[0];
    }
    else if (matches.length == 0) {
        logBroadcast("GetPlayerByIdent", "Couldn't find anyone called " + ident);
    }
    else {
        logBroadcast("GetPlayerByIdent", "Multiple people are called " + ident + ", be more specific.");
    }

    return null;
}

void TryPickPlayer(CRules@ this, CPlayer@ player, int teamNum) {
    // Adds the player to the given team if they are currently spectating and can be picked
    if (player.getTeamNum() == this.getSpectatorTeamNum()) {
        // Don't allow picking of players already on teams
        ChangePlayerTeam(this, player, teamNum);

        string msg = (teamNum == TEAM_BLUE ? "Blue" : "Red") + " team picked " + player.getUsername();
        logBroadcast("TryPickPlayer", msg); 
    }
}

void ForceAllToSpectate(CRules@ this) {
    int specTeam = this.getSpectatorTeamNum();

    for (int i=0; i < getPlayerCount(); i++) {
        CPlayer@ p = getPlayer(i);
        if (p is null || p.getTeamNum() == specTeam) continue;
        ChangePlayerTeam(this, p, specTeam);
    }
}

void ChangePlayerTeam(CRules@ this, CPlayer@ player, int teamNum) {
    RulesCore@ core;
    this.get("core", @core);
    core.ChangePlayerTeam(player, teamNum);
}

void SetBlueCaptain(CRules@ this, CPlayer@ capn) {
    log("SetBlueCaptain", "Setting blue captain to: " + capn.getUsername());
    this.set_string("captain blue", capn.getUsername());
    ChangePlayerTeam(this, capn, TEAM_BLUE);
}

void SetRedCaptain(CRules@ this, CPlayer@ capn) {
    log("SetRedCaptain", "Setting red captain to: " + capn.getUsername());
    this.set_string("captain red", capn.getUsername());
    ChangePlayerTeam(this, capn, TEAM_RED);
}

void StartPickPhase(CRules@ this) {
    log("StartPickPhase", "Starting pick phase!");
    this.set_bool("pick phase", true);
    this.Sync("pick phase", true);

    // Randomize first-pick
    u8 firstPick = XORRandom(2) == 0 ? TEAM_BLUE : TEAM_RED;
    this.set_u8("first pick", firstPick);
    this.Sync("first pick", true);

    getNet().server_SendMsg("Entering pick phase. First pick: " + (firstPick == TEAM_BLUE ? "Blue" : "Red"));

}

void ExitPickPhase(CRules@ this) {
    log("ExitPickPhase", "Exiting pick phase!");
    this.set_bool("pick phase", false);
    getNet().server_SendMsg("Picks finished. LET THE GAME BEGIN!");
}
