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
