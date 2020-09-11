#include <cstrike>
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <common>
#include <csgo_common>

#pragma semicolon 1
#pragma newdecls required

ConVar g_hServerTag;
ConVar g_hReadyMsg;
ConVar g_hUnreadyMsg;
ConVar g_hReadyCounterMsg;
ConVar g_hUnreadyParticipantsMsg;
ConVar g_hHowToReadyMsg;
ConVar g_hUnpauseRequestMsg;

bool g_ReadyCheck[MAXPLAYERS+1];
bool g_ctUnpaused = false;
bool g_tUnpaused = false;
int gameType;
int gameMode;

Handle db;

public Plugin myinfo = {
    name = "Twins Server Manager",
    author = "luciusxsein",
    description = "Server manager with saving stats data and controlling match",
    version = "1.0.0",
    url = "https://github.com/lukasz-sajna/twins-server-manager"
};

public void OnPluginStart() {
    SetConVars();

    AutoExecConfig();
    ServerCommand("mp_warmup_pausetimer 1");
    SetCommandListeners();
    SetTimers();
    SetRegConsoleCommands();
    SetRegAdminCommands();
    HookEvents();

    gameType = GetConVarInt(FindConVar("game_type"));
    gameMode = GetConVarInt(FindConVar("game_mode"));
}

public void SetConVars() {
    g_hServerTag = CreateConVar("sm_servertag", "{GREEN} {GREEN} [{GREEN}OBJ Twins Games]", "Server tag");
    g_hReadyMsg = CreateConVar("sm_readyprint_format", "{SERVER_TAG} {ORANGE}{ORANGE}{NAME} {NORMAL}is {GREEN}ready{NORMAL}!", "Format of the ready output string.");
    g_hUnreadyMsg = CreateConVar("sm_unreadyprint_format", "{SERVER_TAG} {ORANGE}{ORANGE}{NAME} {NORMAL}is {DARK_RED}not ready{NORMAL}!", "Format of the unready output string.");
    g_hReadyCounterMsg = CreateConVar("sm_readyCounterMsg", "{SERVER_TAG} {NORMAL}- {DARK_RED}{PLAYERS_READY} {NORMAL}of {DARK_RED}{PLAYERS} {NORMAL}participants are ready!", "");
    g_hUnreadyParticipantsMsg = CreateConVar("sm_unReadyParticipantsMsg", "{SERVER_TAG} {NORMAL}- not ready participants: {PARTICIPANTS}", "");
    g_hHowToReadyMsg = CreateConVar("sm_howToReadyMsg", "{SERVER_TAG} {NORMAL}- If you are {IS_READY} to play, type !{IS_READY_CMD} in chat", "");
    g_hUnpauseRequestMsg = CreateConVar("sm_unpauseRequest", "{SERVER_TAG} {NORMAL}- The {REQUESTING_TEAM} team wants to unpause. Waiting for the {CONFIRMING_TEAM} team to type {YELLOW}!unpause");
}

public void SetCommandListeners() {
    AddCommandListener(Command_JoinTeam, "jointeam");
}

public void SetTimers() {
    CreateTimer(30.0, Timer_PrintReadyCheckMessage, _, TIMER_REPEAT);
}

public void SetRegConsoleCommands() {
    RegConsoleCmd("sm_ready", Command_Ready, "Set player ready to start the match");
    RegConsoleCmd("sm_unready", Command_Unready, "Set player unready to start the match");
    RegConsoleCmd("sm_pause", Command_Pause, "Requests a pause");
    RegConsoleCmd("sm_unpause", Command_Unpause, "Requests an unpause");
    RegConsoleCmd("sm_mode", Command_Mode, "Requests an unpause");
}

public void SetRegAdminCommands() {
    // RegAdminCmd("sm_restore", Command_Restore, "Restore round from backup");
}

public Action Command_Mode(int client, int args) {
    if (IsWingman()) {
        PrintToChatAll("Wingman");
    } else if (IsCompetitive()) {        
        PrintToChatAll("Competitive");
    } else {
        PrintToChatAll("Other");
    }
}

public void HookEvents() {
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("game_newmap", Event_GameNewMapPre, EventHookMode_Pre);
    HookEvent("round_start", Event_RoundStart);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if(IsValidClient(victim) && InWarmup()) {
        SetEntProp(victim, Prop_Send, "m_iAccount", 16000);
    }
}

public Action Event_GameNewMapPre(Event event, const char[] name, bool dontBroadcast) {
    gameType = GetConVarInt(FindConVar("game_type"));
    gameMode = GetConVarInt(FindConVar("game_mode"));  

    ServerCommand("mp_warmup_pausetimer 1");
    if (InWarmup() && (IsWingman() || IsCompetitive())) {
        SetWeaponDropAfterDeath(0, 0 ,0 ,0);
    }
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {    
    for (int i = 1; i <= MaxClients; i++){
        g_ReadyCheck[i] = false;
    }
}

public Action Command_Ready(int client, int args) {
    if(!InWarmup())
        return Plugin_Handled;

    if (!IsValidClient(client))
        return Plugin_Handled;

    if(g_ReadyCheck[client])
        return Plugin_Handled;

    g_ReadyCheck[client] = true;
    char message[256];
    char name[64];
    GetClientName(client, name, sizeof(name));

    g_hReadyMsg.GetString(message, sizeof(message));
    ReplaceServerTag(message, sizeof(message));
    ReplaceString(message, sizeof(message), "{NAME}", name, false);
    Colorize(message, sizeof(message));

    if (!AllPlayersAreReady()) {
        PrintToChatAll(message);
        PrintReadyParticipants();
        PrintNotReadyParticipants();
    }

    if (AllPlayersAreReady()){
        EndWarmup();
        if (IsWingman() || IsCompetitive()) {
            SetWeaponDropAfterDeath(1, 2, 1, 1);
        }
    }

    return Plugin_Handled;
}

public Action Command_Unready(int client, int args) {
    if(!InWarmup())
        return;
        
    if (!IsValidClient(client))
        return;
        
    if(!g_ReadyCheck[client])
        return;

    g_ReadyCheck[client] = false;    
    char message[256];
    char name[64];
    GetClientName(client, name, sizeof(name));

    g_hUnreadyMsg.GetString(message, sizeof(message));
    ReplaceServerTag(message, sizeof(message));
    ReplaceString(message, sizeof(message), "{NAME}", name, false);
    Colorize(message, sizeof(message));

    PrintToChatAll(message);
    PrintReadyParticipants();
    PrintNotReadyParticipants();
    
}

public Action Command_Pause(int client, int args) {
    if (IsPaused() || !IsValidClient(client) || InWarmup())
        return;

    g_ctUnpaused = false;
    g_tUnpaused = false;

    ServerCommand("mp_pause_match");
    PrintToChatAll("%N has requested a pause.", client);
}

public Action Command_Unpause(int client, int args) {
    if (!IsPaused() || !IsValidClient(client) || InWarmup())
        return;

    int team = GetClientTeam(client);
    if (team == CS_TEAM_T)
        g_tUnpaused = true;
    else if (team == CS_TEAM_CT)
        g_ctUnpaused = true;

    PrintToChatAll("%N requested a unpause", client);

    if (g_tUnpaused && g_ctUnpaused)  {
        ServerCommand("mp_unpause_match");
    } else if (g_tUnpaused && !g_ctUnpaused) {
        PrintUnpauseRequest(client, g_tUnpaused, g_ctUnpaused);
    } else if (!g_tUnpaused && g_ctUnpaused) {
        PrintUnpauseRequest(client, g_tUnpaused, g_ctUnpaused);
    }
}

public Action Command_JoinTeam(int client, const char[] command, int argc) {    
    ServerCommand("mp_warmup_pausetimer 1");
    if (InWarmup() && (IsWingman() || IsCompetitive())) {
        SetWeaponDropAfterDeath(0, 0 ,0 ,0);
    }

    if (!IsValidClient(client))
        return;

    g_ReadyCheck[client] = false;
}

public Action Timer_PrintReadyCheckMessage(Handle timer) {    
    if(!InWarmup())
        return;

    PrintReadyParticipants();
    PrintNotReadyParticipants();
    PrintHowToReadyMsg();
}

public void PrintHowToReadyMsg() { 
    if (AllPlayersAreReady()) 
    {
        return;
    } 

    for (int i = 1; i <= MaxClients; i++){
        if(IsValidClient(i)){
            PrintHowToReady(i, g_ReadyCheck[i]);
        }
    }
}

public int GetReadyPlayers() {
    int playersReady = 0;

    for (int i = 1; i <= MaxClients; i++){
        if(g_ReadyCheck[i] && IsPlayer(i)){
            playersReady++;
        }
    }

    return playersReady;
}

public bool AllPlayersAreReady() {

    if(GetRealClientCount() == 0){
        return false;
    }

    return GetReadyPlayers() == GetRealClientCount();
}

public void PrintReadyParticipants() {
    int playersReady = GetReadyPlayers();
    int playerCount = GetRealClientCount();

    char readyCounterMsg[256];
    
    g_hReadyCounterMsg.GetString(readyCounterMsg, sizeof(readyCounterMsg));
    ReplaceServerTag(readyCounterMsg, sizeof(readyCounterMsg));
    ReplaceStringWithInt(readyCounterMsg, sizeof(readyCounterMsg), "{PLAYERS_READY}", playersReady, false);
    ReplaceStringWithInt(readyCounterMsg, sizeof(readyCounterMsg), "{PLAYERS}", playerCount, false);
    Colorize(readyCounterMsg, sizeof(readyCounterMsg));
    
    PrintToChatAll(readyCounterMsg);
}

public void PrintNotReadyParticipants() {
    char namesArray[MAXPLAYERS+1][MAX_NAME_LENGTH+1];
    char buffer[1024];
    int arrCount = 0;

    for (int i=1; i<= MaxClients;i++)
    {
        if (!g_ReadyCheck[i] && IsPlayer(i))
        {
            GetClientName(i, namesArray[arrCount], sizeof(namesArray[]));
            arrCount++;
        }
    }
    ImplodeStrings(namesArray, arrCount, ", ", buffer, sizeof(buffer));

    char unreadyParticipantsMsg[2560];

    g_hUnreadyParticipantsMsg.GetString(unreadyParticipantsMsg, sizeof(unreadyParticipantsMsg));
    
    ReplaceServerTag(unreadyParticipantsMsg, sizeof(unreadyParticipantsMsg));
    ReplaceString(unreadyParticipantsMsg, sizeof(unreadyParticipantsMsg), "{PARTICIPANTS}", buffer, false);
    Colorize(unreadyParticipantsMsg, sizeof(unreadyParticipantsMsg));

    PrintToChatAll(unreadyParticipantsMsg);
}

public void PrintHowToReady(int client, bool isReady) {
    char message[256];

    g_hHowToReadyMsg.GetString(message, sizeof(message));
    ReplaceServerTag(message, sizeof(message));
    if (!isReady) {
        ReplaceString(message, sizeof(message), "{IS_READY}", "ready", false);
        ReplaceString(message, sizeof(message), "{IS_READY_CMD}", "ready", false);
    }
    else {
        ReplaceString(message, sizeof(message), "{IS_READY}", "not ready", false);
        ReplaceString(message, sizeof(message), "{IS_READY_CMD}", "unready", false);
    }
    Colorize(message, sizeof(message));

    PrintToChat(client, message);
}

public void PrintUnpauseRequest(int client, bool isTerroristsUnpaused, bool isCounterTerroristsUnpaused) {

    for (int i = 1; i <= MaxClients; i++){
        if (!IsPlayer(i))
            return;

        if (GetClientTeam(i) == CS_TEAM_T && isCounterTerroristsUnpaused){
            char message[256];
            g_hUnpauseRequestMsg.GetString(message, sizeof(message));
            CreateUnpauseRequestMessage(message, sizeof(message), isTerroristsUnpaused, isCounterTerroristsUnpaused);
            PrintToChat(i, message);
        } else if (GetClientTeam(i) == CS_TEAM_CT && isTerroristsUnpaused){
            char message[256];
            g_hUnpauseRequestMsg.GetString(message, sizeof(message));
            CreateUnpauseRequestMessage(message, sizeof(message), isTerroristsUnpaused, isCounterTerroristsUnpaused);
            PrintToChat(i, message);
        }
    }
}

public Action CreateUnpauseRequestMessage(char[] message, int size, bool isTerroristsTeamRequested, bool isCounterTerroristsUnpaused) {
    ReplaceServerTag(message, size);
    
    if(isTerroristsTeamRequested) {
        ReplaceString(message, size, "{REQUESTING_TEAM}", "T", false);
        ReplaceString(message, size, "{CONFIRMING_TEAM}", "CT", false);
    } else if (isCounterTerroristsUnpaused) {
        ReplaceString(message, size, "{REQUESTING_TEAM}", "CT", false);
        ReplaceString(message, size, "{CONFIRMING_TEAM}", "T", false);
    }

    Colorize(message, size);
}

public Action ReplaceServerTag(char[] message, int size) {        
    char serverTag[256];    
    g_hServerTag.GetString(serverTag, sizeof(serverTag));
    
    ReplaceString(message, size, "{SERVER_TAG}", serverTag, false);
}

public void SetWeaponDropAfterDeath(int defuser, int grenade, int gun, int taser) {
    ServerCommand("mp_death_drop_defuser %d", defuser);    
    ServerCommand("mp_death_drop_grenade %d", grenade);    
    ServerCommand("mp_death_drop_gun %d", gun);    
    ServerCommand("mp_death_drop_taser %d", taser);
}

public bool IsWingman() {
    return gameType == 0 && gameMode == 2;
}

public bool IsCompetitive() {
    return gameType == 0 && gameMode == 1;
}

public bool IsOther() {
    return gameType != 0;
}