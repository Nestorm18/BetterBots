//=============================================================================
// BBPlayerController
//=============================================================================
// Lets the human player take a place held by a bot:
//  - Joining a full squad moves one of its bots to another squad.
//  - "BBLeader" (console) makes you squad leader, demoting the bot leader.
//
// Console: JoinSquad <n>  (0 = first squad), BBLeader
// Roles held by bots are already freed for humans by the stock game.
//=============================================================================

class BBPlayerController extends ROPlayerController
	config(Game);

function array<ROSquadInfo> BBGetSquads()
{
	local ROMapInfo ROMI;
	local array<ROSquadInfo> Empty;

	ROMI = ROMapInfo(WorldInfo.GetMapInfo());
	if (ROMI == none)
	{
		Empty.Length = 0;
		return Empty;
	}
	return (GetTeamNum() == `AXIS_TEAM_INDEX) ? ROMI.NorthernSquads : ROMI.SouthernSquads;
}

/** If the squad is full, move one of its bots (preferably not the leader) elsewhere */
function BBMakeRoomInSquad(int SquadIndex)
{
	local array<ROSquadInfo> Squads;
	local ROAIController Bot;
	local int i;

	Squads = BBGetSquads();
	if (SquadIndex < 0 || SquadIndex >= Squads.Length || Squads[SquadIndex] == none || Squads[SquadIndex].GetEmptySlot() != -1)
	{
		return;
	}

	for (i = `MAX_ROLES_PER_SQUAD - 1; i >= 0 && Bot == none; i--)
	{
		Bot = ROAIController(Squads[SquadIndex].GetOwner(i));
	}
	if (Bot == none)
	{
		return;	// Full of humans
	}

	Bot.LeaveSquad();

	// Put the bot in another squad with room, if any (it stays squadless otherwise)
	for (i = 0; i < Squads.Length; i++)
	{
		if (i != SquadIndex && Squads[i] != none && Squads[i].GetEmptySlot(true) != -1)
		{
			Bot.JoinSquad(i);
			break;
		}
	}
}

reliable protected server function ServerJoinSquad(int NewSquadIndex, optional bool bViaInvite)
{
	BBMakeRoomInSquad(NewSquadIndex);
	super.ServerJoinSquad(NewSquadIndex, bViaInvite);
}

/** A free attack helicopter (Cobra preferred) and the nearest bot of its team */
function bool BBPickHeliAndBot(out ROVehicleHelicopter Best, out BBAIController BestBot)
{
	local ROVehicleHelicopter H;
	local BBAIController Bot;
	local ROPlayerReplicationInfo BotPRI;
	local float DistSq, BestDistSq;

	Best = none;
	BestBot = none;

	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', H)
	{
		if (H.Health > 0 && !H.bTransportHelicopter && H.Driver == none)
		{
			if (Best == none || (ROHeli_AH1G(H) != none && ROHeli_AH1G(Best) == none))
			{
				Best = H;
			}
		}
	}
	if (Best == none)
	{
		ClientMessage("[BetterBots] No free attack helicopter on this map");
		return false;
	}

	BestDistSq = 1000000000000.0;
	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		BotPRI = ROPlayerReplicationInfo(Bot.PlayerReplicationInfo);
		if (Bot.GetTeamNum() == Best.GetTeamNum() && Bot.Pawn != none && Bot.Pawn.Health > 0 &&
			Vehicle(Bot.Pawn) == none && BotPRI != none && BotPRI.RoleInfo != none && !BotPRI.RoleInfo.bIsTeamLeader)
		{
			DistSq = VSizeSq(Bot.Pawn.Location - Best.Location);
			if (DistSq < BestDistSq)
			{
				BestDistSq = DistSq;
				BestBot = Bot;
			}
		}
	}
	if (BestBot == none)
	{
		ClientMessage("[BetterBots] No bot available on the helicopter's team");
		return false;
	}
	return true;
}

/** The bot currently piloting with the autopilot, if any */
function BBAIController BBFindHeliPilot()
{
	local BBAIController Bot;

	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		if (Bot.BBIsFlyingHeli())
		{
			return Bot;
		}
	}
	return none;
}

/**
 * Helicopter phase 0 test: a friendly bot takes a free attack helicopter
 * (Cobra preferred), climbs to 30 m, hovers, and lands. See the log.
 */
exec function BBHeliTest(optional float HoverSeconds)
{
	local ROVehicleHelicopter Heli;
	local BBAIController Bot;

	if (HoverSeconds <= 0)
	{
		HoverSeconds = 30;
	}
	if (!BBPickHeliAndBot(Heli, Bot))
	{
		return;
	}
	if (Bot.BBStartHeliTest(Heli, HoverSeconds))
	{
		ClientMessage("[BetterBots]"@Bot.PlayerReplicationInfo.PlayerName@"is flying"@Heli.Class.Name);
	}
	else
	{
		ClientMessage("[BetterBots] Heli test failed to start, see Launch.log");
	}
}

/**
 * Helicopter phase 1 test: fly to a point, loiter, come back and land.
 *   BBHeliGoto      -> to where you are standing now
 *   BBHeliGoto 1    -> to objective 1 (A), 2 (B), ...
 * Reuses the bot already flying if there is one.
 */
exec function BBHeliGoto(optional int ObjectiveNumber, optional float LoiterSeconds)
{
	local ROGameInfoTerritories ROGIT;
	local ROVehicleHelicopter Heli;
	local BBAIController Bot;
	local vector Dest;

	if (LoiterSeconds <= 0)
	{
		LoiterSeconds = 20;
	}

	if (ObjectiveNumber > 0)
	{
		ROGIT = ROGameInfoTerritories(WorldInfo.Game);
		if (ROGIT == none || ObjectiveNumber > ROGIT.Objectives.Length || ROGIT.Objectives[ObjectiveNumber - 1] == none)
		{
			ClientMessage("[BetterBots] No objective"@ObjectiveNumber);
			return;
		}
		Dest = ROGIT.Objectives[ObjectiveNumber - 1].Location;
		ClientMessage("[BetterBots] Heli to objective"@ROGIT.Objectives[ObjectiveNumber - 1].ObjName);
	}
	else if (Pawn != none)
	{
		Dest = Pawn.Location;
	}
	else
	{
		ClientMessage("[BetterBots] You need to be alive to send the heli to you");
		return;
	}

	Bot = BBFindHeliPilot();
	if (Bot != none)
	{
		Bot.BBHeliRetask('Goto', Dest, LoiterSeconds);
		ClientMessage("[BetterBots] Retasked"@Bot.PlayerReplicationInfo.PlayerName);
		return;
	}

	if (!BBPickHeliAndBot(Heli, Bot))
	{
		return;
	}
	if (Bot.BBStartHeli(Heli, 'Goto', Dest, LoiterSeconds))
	{
		ClientMessage("[BetterBots]"@Bot.PlayerReplicationInfo.PlayerName@"is flying"@Heli.Class.Name);
	}
	else
	{
		ClientMessage("[BetterBots] Heli flight failed to start, see Launch.log");
	}
}

/** Send the flying bot back to its take-off point to land */
exec function BBHeliHome()
{
	local BBAIController Bot;

	Bot = BBFindHeliPilot();
	if (Bot == none)
	{
		ClientMessage("[BetterBots] No bot is flying a helicopter");
		return;
	}
	Bot.BBHeliRetask('Home', Bot.BBHeliHome, 0);
	ClientMessage("[BetterBots]"@Bot.PlayerReplicationInfo.PlayerName@"returning to base");
}

exec function BBLeader()
{
	local ROPlayerReplicationInfo ROPRI;
	local Controller CurrentSL;

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || ROPRI.Squad == none || ROPRI.RoleIndex == `ROLE_INDEX_NONE)
	{
		ClientMessage("[BetterBots] Join a squad first (JoinSquad <n>)");
		return;
	}
	if (ROPRI.RoleIndex == `ROLE_INDEX_SQUADLEADER)
	{
		ClientMessage("[BetterBots] You are already the squad leader");
		return;
	}

	CurrentSL = ROPRI.Squad.GetSquadLeader();
	if (CurrentSL != none && ROAIController(CurrentSL) == none)
	{
		ClientMessage("[BetterBots] The squad leader is a human player");
		return;
	}

	if (ROPRI.Squad.PromoteToSquadLeader(ROPRI.RoleIndex))
	{
		ClientMessage("[BetterBots] You are now the squad leader");
	}
	else
	{
		ClientMessage("[BetterBots] Could not make you squad leader");
	}
}

defaultproperties
{
}
