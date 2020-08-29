#include <cstrike>
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <common>
#include <csgo_common>

#pragma semicolon 1
#pragma newdecls required

Handle db;

public Plugin myinfo = {
    name = "Twins Server Manager",
    author = "luciusxsein",
    description = "Server manager with saving stats data and controlling match",
    version = "1.0.0",
    url = "https://github.com/lukasz-sajna/twins-server-manager"
};

public void OnPluginStart() {    
    AutoExecConfig();
    RegConsoleCmd("!test", Command_Test, "Test command");
}

public Action Command_Test(int client, int args) {
    PrintToChatAll("%N has typed test command", client);
}