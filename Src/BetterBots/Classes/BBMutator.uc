//=============================================================================
// BBMutator
//=============================================================================
// Swaps the stock bot controller for BBAIController, which picks objectives
// by priority, actually defends, and recovers when stuck.
//
// Usage (offline): open <map>?MinPlayers=32?mutator=BetterBots.BBMutator
//=============================================================================

class BBMutator extends ROMutator
	config(Mutator_BetterBots);

var int BBStatusLogs;
var int BBWantedPlayers;		// From ?MinPlayers= (or ?Bots=), defaults to 64
var bool bBBLimitsFixed;

function PreBeginPlay()
{
	local ROGameInfo ROGI;

	super.PreBeginPlay();

	ROGI = ROGameInfo(WorldInfo.Game);
	if (ROGI != none)
	{
		ROGI.AIControllerClass = class'BBAIController';
		// Only offline, and only the standard PC class (not console)
		if (WorldInfo.NetMode == NM_Standalone && ROGI.PlayerControllerClass == class'ROPlayerController')
		{
			ROGI.PlayerControllerClass = class'BBPlayerController';
		}
		`log("[BetterBots] Bot controller replaced with"@ROGI.AIControllerClass);
	}
}

function InitMutator(string Options, out string ErrorMessage)
{
	local ROGameInfo ROGI;

	super.InitMutator(Options, ErrorMessage);

	BBWantedPlayers = class'GameInfo'.static.GetIntOption(Options, "MinPlayers", 64);
	BBWantedPlayers = class'GameInfo'.static.GetIntOption(Options, "Bots", BBWantedPlayers);
	BBWantedPlayers = Clamp(BBWantedPlayers, 2, 64);

	// Must happen now: the game creates squads and role slots from MaxPlayers
	// in PreBeginPlay (2 squads for <=12 players, 10 for >32)
	ROGI = ROGameInfo(WorldInfo.Game);
	if (ROGI != none)
	{
		ROGI.MaxPlayers = Max(ROGI.MaxPlayers, Min(BBWantedPlayers, ROGI.MaxPlayersAllowed));
		`log("[BetterBots] MaxPlayers set early to"@ROGI.MaxPlayers);
	}
}

/**
 * A map opened from the console runs as a single-player game: MaxPlayers is 1,
 * so the game wants only 1 player and never adds bots or starts the round.
 */
function BBFixPlayerLimits(ROGameInfo ROGI)
{
	ROGI.MaxPlayers = Max(ROGI.MaxPlayers, Min(BBWantedPlayers, ROGI.MaxPlayersAllowed));
	ROGI.DesiredPlayerCount = Min(BBWantedPlayers, ROGI.MaxPlayers);
	ROGI.DesiredPlayerCount = Min(ROGI.DesiredPlayerCount, Max(ROGI.GetBotCapableRoles(), 2));
	bBBLimitsFixed = true;
	`log("[BetterBots] Player limits set: MaxPlayers="$ROGI.MaxPlayers@"Desired="$ROGI.DesiredPlayerCount@"(wanted"@BBWantedPlayers$")");
}

function PostBeginPlay()
{
	super.PostBeginPlay();
	SetTimer(2.0, true, 'BBFillBots');
}

/**
 * The stock game only adds bots during reinforcement waves, which may never
 * happen when the map is opened from the console. Top the bots up ourselves.
 */
function BBFillBots()
{
	local ROGameInfo ROGI;

	ROGI = ROGameInfo(WorldInfo.Game);
	if (ROGI == none)
	{
		return;
	}

	if (!bBBLimitsFixed)
	{
		BBFixPlayerLimits(ROGI);
	}

	if (BBStatusLogs < 10)
	{
		BBStatusLogs++;
		`log("[BetterBots] RoundActive="$ROGI.bRoundActive@"StartScreen="$ROGI.bInRoundStartScreen@
			"Desired="$ROGI.DesiredPlayerCount@"Bots="$ROGI.NumBots@"Players="$ROGI.NumPlayers@
			"MaxPlayers="$ROGI.MaxPlayers@"NeedPlayers="$ROGI.NeedPlayers());
	}

	// Wait for the local player so bots don't fill the slot meant for them
	if (ROGI.NumPlayers > 0 && ROGI.NeedPlayers() && !ROGI.IsTimerActive('AddBotsOnInterval'))
	{
		ROGI.AddBotsOnInterval();
	}
}

defaultproperties
{
}
