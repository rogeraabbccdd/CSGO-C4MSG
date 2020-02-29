#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <kento_csgocolors>

#define PLUGIN_VERSION "1.0"

#pragma newdecls required

#define SPEC 1
#define TR 2
#define CT 3

Handle g_hTimer_Countdown = INVALID_HANDLE;

float g_fExplosionTime, g_fCounter, g_fTimer;
char CHAT_PREFIX[16] = "C4MSG";

float g_DetonateTime = 0.0;
float g_DefuseEndTime = 0.0;
int g_DefusingClient = -1;
bool g_CurrentlyDefusing = false;

ConVar g_hCvarTimer;

public Plugin myinfo = 
{
  name = "C4 Messages",
  author = "Kento",
  description = "C4 countdown and messages.",
  version = "1.0",
  url = "http://steamcommunity.com/id/kentomatoryoshika/"
};

public void OnPluginStart()
{
  LoadTranslations("kento.c4msg.phrases");

  g_hCvarTimer = FindConVar("mp_c4timer");
  g_hCvarTimer.AddChangeHook(OnConVarChanged);
  
  HookEvent("bomb_planted", EventBombPlanted, EventHookMode_Pre);
  HookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
  HookEvent("bomb_exploded", EventBombExploded, EventHookMode_PostNoCopy);
  HookEvent("bomb_defused", EventBombDefused, EventHookMode_Post);
  HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Pre );
  
  // for bomb messages from 
  // https://github.com/Metapyziks/csgo-retakes-ziksallocator
  HookEvent("bomb_planted", Event_Bomb_Planted_Post, EventHookMode_Post);
  HookEvent("bomb_begindefuse", Event_Bomb_Defuse_Begin_Post, EventHookMode_Post);
  HookEvent("bomb_abortdefuse", Event_Bomb_Defuse_Abort_Post, EventHookMode_Post);
  HookEvent("bomb_exploded", Event_Bomb_Exploded_Post, EventHookMode_Post);

  AutoExecConfig(true, "kento_c4msg");
}

public void OnConfigsExecuted()
{
  g_fTimer = g_hCvarTimer.FloatValue;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
  if(convar == g_hCvarTimer)	g_fTimer = g_hCvarTimer.FloatValue;
}

public void OnMapStart()
{
  for(int i = 1;i<=10;i++){
    char buffer[512], file[512], buffer2[512];
    Format(buffer, sizeof(buffer), "c4timer/kento/%dsec.mp3", i);
    Format(file, sizeof(file), "sound/%s", buffer);
    Format(buffer2, sizeof(buffer2), "*/%s", buffer);
    FakePrecacheSound(buffer2);
    AddFileToDownloadsTable(file);
  }
}

stock void FakePrecacheSound(const char[] szPath)
{
  AddToStringTable(FindStringTable("soundprecache"), szPath);
}

public Action Event_Bomb_Planted_Post(Event event, const char[]name, bool dontBroadcast)
{
  BombTime_BombPlanted();
}

public Action Event_Bomb_Defuse_Begin_Post(Event event, const char[]name, bool dontBroadcast)
{
  BombTime_BombBeginDefuse(event);
}

public Action Event_Bomb_Defuse_Abort_Post(Event event, const char[]name, bool dontBroadcast)
{
  BombTime_BombAbortDefuse(event);
}

public Action Event_Bomb_Exploded_Post(Event event, const char[]name, bool dontBroadcast)
{
  BombTime_BombExploded();
}

public Action Event_PlayerDeath( Event event, const char[] name, bool dontBroadcast )
{
  BombTime_PlayerDeath( event );
}

public Action EventRoundStart(Handle event, const char[]name, bool dontBroadcast)
{
  if(g_hTimer_Countdown != INVALID_HANDLE && CloseHandle(g_hTimer_Countdown))
    g_hTimer_Countdown = INVALID_HANDLE;
    
  g_DetonateTime = 0.0;
  g_DefuseEndTime = 0.0;
  g_DefusingClient = -1;
  g_CurrentlyDefusing = false;
}

public Action EventBombPlanted(Handle event, const char[]name, bool dontBroadcast)
{
  g_fCounter = g_fTimer - 1.0;
  g_fExplosionTime = GetEngineTime() + g_fTimer;
    
  g_hTimer_Countdown = CreateTimer(((g_fExplosionTime - g_fCounter) - GetEngineTime()), TimerCountdown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

  return Plugin_Continue;
}

public Action EventBombDefused(Event event, const char[]name, bool dontBroadcast)
{
  if(g_hTimer_Countdown != INVALID_HANDLE)
  {
    KillTimer(g_hTimer_Countdown);
    g_hTimer_Countdown = INVALID_HANDLE;
  }
  
  BombTime_BombDefused(event);
}

public Action EventBombExploded(Handle event, const char[]name, bool dontBroadcast)
{
  if(g_hTimer_Countdown != INVALID_HANDLE)
  {
    KillTimer(g_hTimer_Countdown);
    g_hTimer_Countdown = INVALID_HANDLE;
  }
}

public Action TimerCountdown(Handle timer, any data)
{
  BombMessage(RoundToFloor(g_fCounter));
  
  g_fCounter--;
  if(g_fCounter < 0)
  {
    KillTimer(g_hTimer_Countdown);
    g_hTimer_Countdown = INVALID_HANDLE;
  }
}

public void BombMessage(int count)
{
  char sBuffer[192];
  
  if(count >= 0 && count <= 10)
  {	
    for(int i = 1; i <= MaxClients; i++)
    {
      Format(sBuffer, sizeof(sBuffer), "countdown %i", count);
      Format(sBuffer, sizeof(sBuffer), "%T", sBuffer, i, count);
      
      if(IsValidClient(i) && !IsFakeClient(i))
      {
        PrintHintText(i, sBuffer);
        if(count > 0) {
          char snd[128];
          Format(snd, sizeof(snd), "*/c4timer/kento/%dsec.mp3", count);
          EmitSoundToClient(i, snd);
        }
      }
    }
  }
}

stock bool IsValidClient(int client)
{
  if (client <= 0) return false;
  if (client > MaxClients) return false;
  if (!IsClientConnected(client)) return false;
  return IsClientInGame(client);
}

void BombTime_PlayerDeath( Handle event )
{
  int victim = GetClientOfUserId(GetEventInt(event, "userid" ));
  int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

  if ( g_DefusingClient != victim || !g_CurrentlyDefusing ) return;
  if ( !IsValidClient( victim ) ) return;
  if ( !IsValidClient( attacker ) ) return;

  float timeRemaining = g_DefuseEndTime - GetGameTime();
  if ( timeRemaining > 0.0 )
  {
    char defuserName[64];
    GetClientName( victim, defuserName, sizeof(defuserName) );

    char timeString[32];
    FloatToStringFixedPoint( timeRemaining, 2, timeString, sizeof(timeString) );
    
    for(int i = 1; i <= MaxClients; i++)
    {
      if(IsValidClient(i) && !IsFakeClient(i))
      {
        CPrintToChat(i,  "%T", "DefuserDiedTimeLeftMessage", i, CHAT_PREFIX, defuserName, timeString );
      }
    }
  }
  else
  {
    char attackerName[64];
    GetClientName( attacker, attackerName, sizeof(attackerName) );

    char timeString[32];
    FloatToStringFixedPoint( -timeRemaining, 2, timeString, sizeof(timeString) );
    
    for(int i = 1; i <= MaxClients; i++)
    {
      if(IsValidClient(i) && !IsFakeClient(i))
      {
        CPrintToChat(i, "%T", "PostDefuseKillTimeMessage", i, CHAT_PREFIX, attackerName, timeString );
      }
    }
  }
}

void BombTime_BombPlanted()
{
  g_DetonateTime = GetGameTime() + GetConVarInt(FindConVar( "mp_c4timer" ));
  g_DefusingClient = -1;
  g_CurrentlyDefusing = false;
}

void BombTime_BombDefused( Event event )
{
  int defuser = GetClientOfUserId( event.GetInt( "userid" ) );

  if ( !IsValidClient( defuser ) ) return;

  float timeRemaining = g_DetonateTime - GetGameTime();

  char defuserName[64];
  GetClientName( defuser, defuserName, sizeof(defuserName) );

  char timeString[32];
  FloatToStringFixedPoint( timeRemaining, 2, timeString, sizeof(timeString) );

  for(int i = 1; i <= MaxClients; i++)
  {
    if(IsValidClient(i) && !IsFakeClient(i))
    {
      CPrintToChat(i, "%T", "SuccessfulDefuseTimeLeftMessage", i, CHAT_PREFIX, defuserName, timeString );
    }
  }
}

void BombTime_BombBeginDefuse( Event event )
{
  int defuser = GetClientOfUserId( event.GetInt( "userid" ) );
  bool hasKit = event.GetBool( "haskit" );

  float endTime = GetGameTime() + (hasKit ? 5.0 : 10.0);
  
  g_CurrentlyDefusing = true;

  if ( g_DefusingClient == -1 || g_DefuseEndTime < g_DetonateTime )
  {
    g_DefuseEndTime = endTime;
    g_DefusingClient = defuser;

    int bomb = FindEntityByClassname( -1, "weapon_c4" );
    if ( !BombTime_AnyLivingTerrorists() && bomb != -1 )
    {   
      float defuseLength = GetEntPropFloat( bomb, Prop_Send, "m_flDefuseLength", 0 );
      SetEntPropFloat( bomb, Prop_Send, "m_flDefuseLength", defuseLength - 4, 0 );
    } 
  }
}

void BombTime_BombAbortDefuse( Event event )
{
  int defuser = GetClientOfUserId( event.GetInt( "userid" ) );

  if ( g_DefusingClient == defuser )
  {
    g_CurrentlyDefusing = false;
  }
}

void BombTime_BombExploded()
{
  float timeRemaining = g_DefuseEndTime - g_DetonateTime;

  if ( IsValidClient( g_DefusingClient ) && timeRemaining >= 0.0 )
  {
    char defuserName[64];
    GetClientName( g_DefusingClient, defuserName, sizeof(defuserName) );

    char timeString[32];
    FloatToStringFixedPoint( timeRemaining, 2, timeString, sizeof(timeString) );

    for(int i = 1; i <= MaxClients; i++)
    {
      if(IsValidClient(i) && !IsFakeClient(i))
      {
        CPrintToChat(i, "%T", "BombExplodedTimeLeftMessage", i, CHAT_PREFIX, defuserName, timeString );
      }
    }
  }
}

bool BombTime_AnyLivingTerrorists()
{
  for ( int client = 1; client <= MaxClients; ++client )
  {
    if ( !IsValidClient( client )) continue;

    int team = GetClientTeam( client );
    if ( team != CS_TEAM_T ) continue;

    if ( IsPlayerAlive( client ) ) return true;
  }
  return false;
}

int FloatToStringFixedPoint( float value, int fractionalDigits, char[] buffer, int maxLength )
{
  if ( fractionalDigits == 0 )
  {
    return IntToString( RoundFloat( value ), buffer, maxLength );
  }

  int scale = RoundFloat( Pow( 10.0, fractionalDigits * 1.0 ) );
  int valueInt = view_as<int>( RoundFloat( value * scale ) );

  int offset = IntToString( valueInt / scale, buffer, maxLength );
  if ( offset >= maxLength - 2 ) return offset;

  buffer[offset++] = '.';

  for ( int i = 0; i < fractionalDigits && offset < maxLength - 1; ++i, ++offset )
  {
    scale /= 10;
    buffer[offset] = '0' + ((valueInt / scale) % 10);
  }

  buffer[offset] = 0;

  return offset;
}