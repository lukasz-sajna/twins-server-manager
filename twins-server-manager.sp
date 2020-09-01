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

bool g_ReadyCheck[MAXPLAYERS+1];

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
}

public void SetConVars() {
    g_hServerTag = CreateConVar("sm_servertag", "{GREEN} {GREEN} [{GREEN}OBJ Twins Games]", "Server tag");
    g_hReadyMsg = CreateConVar("sm_readyprint_format", "{SERVER_TAG} {ORANGE}{ORANGE}{NAME} {NORMAL}is {GREEN}ready{NORMAL}!", "Format of the ready output string.");
    g_hUnreadyMsg = CreateConVar("sm_unreadyprint_format", "{SERVER_TAG} {ORANGE}{ORANGE}{NAME} {NORMAL}is {DARK_RED}not ready{NORMAL}!", "Format of the unready output string.");
    g_hReadyCounterMsg = CreateConVar("sm_readyCounterMsg", "{SERVER_TAG} {NORMAL}- {DARK_RED}{PLAYERS_READY} {NORMAL}of {DARK_RED}{PLAYERS} {NORMAL}participants are ready!", "");
    g_hUnreadyParticipantsMsg = CreateConVar("sm_unReadyParticipantsMsg", "{SERVER_TAG} {NORMAL}- not ready participants: {PARTICIPANTS}", "");
    g_hHowToReadyMsg = CreateConVar("sm_howToReadyMsg", "{SERVER_TAG} {NORMAL}- If you are {IS_READY} to play, type !{IS_READY_CMD} in chat", "");
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
}

public Action Command_Ready(int client, int args) {
    if(!InWarmup())
        return;

    if (!IsValidClient(client))
        return;

    if(g_ReadyCheck[client])
        return;

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
    }
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

public Action Command_JoinTeam(int client, const char[] command, int argc) {    
    ServerCommand("mp_warmup_pausetimer 1");

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

public Action ReplaceServerTag(char[] message, int size) {        
    char serverTag[256];    
    g_hServerTag.GetString(serverTag, sizeof(serverTag));
    
    ReplaceString(message, size, "{SERVER_TAG}", serverTag, false);
}