//=============================================================================
// BBHeliManager
//=============================================================================
// Coordinates bot helicopter crews for both teams (only the US has helis in
// the stock game, but nothing here assumes it).
//
// - Crews: gives bots the pilot role and puts them in free helicopters,
//   30 s after the human first spawns so they can pick a pilot role first.
//   Cobra/Bushranger gunners (pilot role) only when every heli has a pilot.
//   Door gunners (any role) on Hueys and Bushrangers.
// - Passengers: bots near a waiting transport (bot or human pilot) board it
//   when the front is far; they get off when it lands near the objective.
// - Human priority: a human with a pilot role standing by a landed bot heli
//   takes it; picking a pilot role held by bots frees one (a bot on the
//   ground at once, otherwise the nearest heli comes back and lands).
// - Shared memory: danger spots where helis were hit (fades in ~3 min) and
//   enemies marked by the Loach.
//=============================================================================

class BBHeliManager extends Info;

struct BBThreat
{
	var vector	Loc;
	var float	Amount;
	var float	Time;
	var byte	Team;
};

struct BBMark
{
	var Pawn	P;
	var vector	Loc;
	var float	Time;
	var byte	Team;
};

struct BBStrike
{
	var Pawn				P;
	var float				Time;
	var byte				Team;
	var ROVehicleHelicopter	Caller;
};

const BB_ThreatLife			= 180.0;	// Seconds until a danger spot is forgotten
const BB_MarkLife			= 20.0;
const BB_HumanGrace			= 15.0;		// Seconds the human gets to pick a pilot role first
const BB_CrewPickupDist		= 3000.0;	// Alive bots this close to a heli can be crew/passengers (60 m)
const BB_HumanTakeDist		= 750.0;	// 15 m
const BB_HumanReserveDist	= 2500.0;	// Free helis this close to a human pilot are left for them
const BB_FrontFarDist		= 15000.0;	// 300 m: closer than this, bots walk instead of flying

var array<BBThreat>	Threats;
var array<BBMark>	Marks;
var array<BBStrike>	Strikes;			// "Someone is shooting at me" calls for the attack helis
var bool			bDebugDraw;
var float			NextDebugText;
var float			HumanSpawnTime;		// First time the human had a pawn (-1 = not yet)
var float			StartTime;

// One pending "give me a pilot role" request from the human
var BBPlayerController	CedePC;
var class<RORoleInfo>	CedeRoleClass;
var WeaponSelectionInfo	CedeWeapons;
var class<ROVehicle>	CedeTank;
var bool				bCedeAllowTeamTank, bCedeDesiredContext, bCedeCloseMenu;
var BBAIController		CedeBot;
var float				CedeTime;

var float			NextBoardTime;
var float			NextLog;

event PostBeginPlay()
{
	super.PostBeginPlay();
	HumanSpawnTime = -1;
	StartTime = WorldInfo.TimeSeconds;
	SetTimer(1.0, true, 'BBTick');
	`log("[BetterBots][Heli] Helicopter manager running");
}

static function BBHeliManager Get(WorldInfo WI)
{
	local BBHeliManager M;

	foreach WI.DynamicActors(class'BBHeliManager', M)
	{
		return M;
	}
	return none;
}

/*-----------------------------------------------------------------------------
	Helicopter types and seats
-----------------------------------------------------------------------------*/

static function name HeliType(ROVehicleHelicopter H)
{
	if (H == none)
	{
		return '';
	}
	if (H.bTransportHelicopter)
	{
		return 'Lift';
	}
	if (H.bIsGunship)
	{
		return 'Gunship';
	}
	if (ROHeli_OH6(H) != none)
	{
		return 'Scout';
	}
	return 'Attack';
}

static function string HeliName(ROVehicleHelicopter H)
{
	switch (HeliType(H))
	{
		case 'Lift':	return "Huey";
		case 'Gunship':	return "Bushranger";
		case 'Scout':	return "Loach";
	}
	return "Cobra";
}

static function bool IsPassengerSeat(ROVehicleHelicopter H, int i)
{
	return i > 0 && i < H.Seats.Length && !H.Seats[i].bNonEnterable && Left(H.Seats[i].TurretVarPrefix, 9) ~= "Passenger";
}

static function bool IsDoorGunSeat(ROVehicleHelicopter H, int i)
{
	return i > 0 && i < H.Seats.Length && !H.Seats[i].bNonEnterable && Left(H.Seats[i].TurretVarPrefix, 6) ~= "DoorMG";
}

/** Cobra and Bushranger copilots man a weapon; the seat needs a pilot role */
static function bool IsGunnerCopilotSeat(ROVehicleHelicopter H, int i)
{
	return i > 0 && i == H.SeatIndexCopilot && i < H.Seats.Length && !H.Seats[i].bNonEnterable && H.Seats[i].GunClass != none;
}

static function Controller SeatController(ROVehicleHelicopter H, int i)
{
	if (i == 0)
	{
		return H.Controller;
	}
	if (i > 0 && i < H.Seats.Length && H.Seats[i].SeatPawn != none)
	{
		return H.Seats[i].SeatPawn.Controller;
	}
	return none;
}

static function bool SeatFree(ROVehicleHelicopter H, int i)
{
	if (i == 0)
	{
		return H.Driver == none && H.Controller == none;
	}
	return i > 0 && i < H.Seats.Length && !H.Seats[i].bNonEnterable &&
		(H.Seats[i].SeatPawn == none || H.Seats[i].SeatPawn.Controller == none);
}

function int NumPassengers(ROVehicleHelicopter H, out int NumHumans)
{
	local int i, N;
	local Controller C;

	NumHumans = 0;
	for (i = 1; i < H.Seats.Length; i++)
	{
		if (IsPassengerSeat(H, i))
		{
			C = SeatController(H, i);
			if (C != none)
			{
				N++;
				if (PlayerController(C) != none)
				{
					NumHumans++;
				}
			}
		}
	}
	return N;
}

function int FreePassengerSeat(ROVehicleHelicopter H)
{
	local int i;

	for (i = 1; i < H.Seats.Length; i++)
	{
		if (IsPassengerSeat(H, i) && SeatFree(H, i) && !BBSeatClaimed(H, i))
		{
			return i;
		}
	}
	return -1;
}

function bool HeliOnGround(ROVehicleHelicopter H)
{
	return H.bVehicleOnGround || H.bWasChassisTouchingGroundLastTick;
}

function vector HeliHome(ROVehicleHelicopter H)
{
	if (H.ParentFactory != none)
	{
		return H.ParentFactory.Location;
	}
	return H.Location;
}

function bool HeliUsable(ROVehicleHelicopter H)
{
	return H != none && H.Health > 0 && !H.bDeleteMe && !H.bEngineDestroyed && !H.bMainRotorDestroyed &&
		!H.bTailRotorDestroyed && !H.bIsInverted;
}

/*-----------------------------------------------------------------------------
	Roles
-----------------------------------------------------------------------------*/

/** Index in the team's role list of the (combat or transport) pilot role, -1 if none */
function int PilotRoleIndex(byte Team, bool bTransport)
{
	local ROMapInfo ROMI;
	local array<RORoleCount> Roles;
	local int i;

	ROMI = ROMapInfo(WorldInfo.GetMapInfo());
	if (ROMI == none)
	{
		return -1;
	}
	Roles = (Team == `AXIS_TEAM_INDEX) ? ROMI.NorthernRoles : ROMI.SouthernRoles;
	for (i = 0; i < Roles.Length; i++)
	{
		if (Roles[i].RoleInfoClass != none && Roles[i].RoleInfoClass.default.bIsPilot &&
			Roles[i].RoleInfoClass.default.bIsTransportPilot == bTransport && Roles[i].Count > 0)
		{
			return i;
		}
	}
	return -1;
}

function class<RORoleInfo> PilotRoleClass(byte Team, bool bTransport)
{
	local ROMapInfo ROMI;
	local int i;

	i = PilotRoleIndex(Team, bTransport);
	ROMI = ROMapInfo(WorldInfo.GetMapInfo());
	if (i < 0 || ROMI == none)
	{
		return none;
	}
	return (Team == `AXIS_TEAM_INDEX) ? ROMI.NorthernRoles[i].RoleInfoClass : ROMI.SouthernRoles[i].RoleInfoClass;
}

/** Free slots in a pilot role (counting bots and humans) */
function int PilotSlotsFree(byte Team, bool bTransport)
{
	local ROMapInfo ROMI;
	local int i;

	i = PilotRoleIndex(Team, bTransport);
	ROMI = ROMapInfo(WorldInfo.GetMapInfo());
	if (i < 0 || ROMI == none)
	{
		return 0;
	}
	if (Team == `AXIS_TEAM_INDEX)
	{
		return ROMI.NorthernRoles[i].Count - ROMI.NorthernRolesTaken[i].TotalTaken;
	}
	return ROMI.SouthernRoles[i].Count - ROMI.SouthernRolesTaken[i].TotalTaken;
}

static function bool HasPilotRole(Controller C, bool bTransport)
{
	local ROPlayerReplicationInfo ROPRI;

	ROPRI = (C != none) ? ROPlayerReplicationInfo(C.PlayerReplicationInfo) : none;
	return ROPRI != none && ROPRI.RoleInfo != none && ROPRI.RoleInfo.bIsPilot && ROPRI.RoleInfo.bIsTransportPilot == bTransport;
}

/*-----------------------------------------------------------------------------
	Main tick
-----------------------------------------------------------------------------*/

function bool BotsMayCrew()
{
	local PlayerController PC;

	if (HumanSpawnTime < 0)
	{
		foreach WorldInfo.AllControllers(class'PlayerController', PC)
		{
			if (PC.Pawn != none && PC.Pawn.Health > 0)
			{
				HumanSpawnTime = WorldInfo.TimeSeconds;
				`log("[BetterBots][Heli] Human spawned, bots take helicopters in"@int(BB_HumanGrace)$"s");
				break;
			}
		}
	}
	if (HumanSpawnTime >= 0)
	{
		return WorldInfo.TimeSeconds - HumanSpawnTime > BB_HumanGrace;
	}
	// Nobody spawned (spectating): don't wait forever
	return WorldInfo.TimeSeconds - StartTime > 120.0;
}

function BBTick()
{
	local ROVehicleHelicopter H;
	local bool bMayCrew, bAllPiloted, bHumanAboard;
	local int NumHelis;

	BBExpireMemory();
	bMayCrew = BotsMayCrew();

	// The human's own heli gets its crew first (gunners freed by a heli swap go there)
	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', H)
	{
		if (HeliUsable(H) && PlayerController(H.Controller) != none)
		{
			BBCrewGuns(H, true);
		}
	}

	// First pass: pilots. Gunners only once every usable heli has a pilot.
	bAllPiloted = true;
	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', H)
	{
		if (!HeliUsable(H))
		{
			continue;
		}
		NumHelis++;
		BBCheckHumanTakeover(H);
		if (H.Driver == none && H.Controller == none)
		{
			// A human in the gunner/passenger seat gets a bot pilot right away
			if ((bMayCrew || BBHumanAboard(H)) && HeliOnGround(H) && !BBReservedForHuman(H))
			{
				BBAssignCrew(H, 0);
			}
			if (H.Driver == none && !BBPilotOnTheWay(H))
			{
				bAllPiloted = false;
			}
		}
	}

	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', H)
	{
		if (!HeliUsable(H) || (H.Driver == none && !BBPilotOnTheWay(H)))
		{
			continue;
		}
		bHumanAboard = BBHumanAboard(H);
		if (bMayCrew || bHumanAboard)
		{
			// A human's heli gets its gunner first, even if other helis lack pilots
			BBCrewGuns(H, bAllPiloted || bHumanAboard);
		}
		BBBoardPassengers(H);
	}

	BBCheckCede();
	BBUpdateHeliSpawns();

	if (WorldInfo.TimeSeconds > NextLog && NumHelis > 0)
	{
		NextLog = WorldInfo.TimeSeconds + 30.0;
		BBLogStatus();
	}
}

function BBLogStatus()
{
	local ROVehicleHelicopter H;
	local int NumHumans;

	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', H)
	{
		`log("[BetterBots][Heli] Status"@HeliName(H)@"team"@H.GetTeamNum()@"health"@H.Health$"/"$H.HealthMax@
			"pilot"@((H.Controller != none && H.Controller.PlayerReplicationInfo != none) ? H.Controller.PlayerReplicationInfo.PlayerName : "none")@
			"passengers"@NumPassengers(H, NumHumans)@"ground"@HeliOnGround(H)@"threats"@Threats.Length@"marks"@Marks.Length);
	}
}

/*-----------------------------------------------------------------------------
	Crew assignment
-----------------------------------------------------------------------------*/

/** A free heli next to a human with the matching pilot role is theirs */
function bool BBReservedForHuman(ROVehicleHelicopter H)
{
	local PlayerController PC;

	foreach WorldInfo.AllControllers(class'PlayerController', PC)
	{
		// Only humans on foot (one already sitting in a heli wants a crew, not the cockpit)
		if (PC.Pawn != none && PC.Pawn.Health > 0 && Vehicle(PC.Pawn) == none && PC.GetTeamNum() == H.GetTeamNum() &&
			HasPilotRole(PC, H.bTransportHelicopter) && VSizeSq(PC.Pawn.Location - H.Location) < BB_HumanReserveDist * BB_HumanReserveDist)
		{
			return true;
		}
	}
	return false;
}

/** A human sits in one of the heli's seats */
function bool BBHumanAboard(ROVehicleHelicopter H)
{
	local int i;

	if (PlayerController(H.Controller) != none)
	{
		return true;
	}
	for (i = 1; i < H.Seats.Length; i++)
	{
		if (PlayerController(SeatController(H, i)) != none)
		{
			return true;
		}
	}
	return false;
}

/**
 * A human of this heli's team is still choosing at the heli base: sitting in
 * another landed heli there, or on foot near the helis. Bot helis at base
 * wait for them, so a human can still swap helis and get a crew again.
 */
function bool BBHumanAtHeliBase(ROVehicleHelicopter H)
{
	local PlayerController PC;
	local ROVehicleHelicopter Other;
	local bool bNear;

	foreach WorldInfo.AllControllers(class'PlayerController', PC)
	{
		if (PC.Pawn == none || PC.Pawn.Health <= 0 || PC.GetTeamNum() != H.GetTeamNum())
		{
			continue;
		}
		Other = ROVehicleHelicopter(PC.Pawn);
		if (Other == none && ROWeaponPawn(PC.Pawn) != none)
		{
			Other = ROVehicleHelicopter(ROWeaponPawn(PC.Pawn).MyVehicle);
		}
		if (Other != none)
		{
			// In a heli of their own, still on the ground at base (ours handles its own wait)
			if (Other != H && HeliOnGround(Other) && VSize(Other.Location - HeliHome(Other)) < 4000.0)
			{
				return true;
			}
			continue;
		}
		if (Vehicle(PC.Pawn) != none)
		{
			continue;
		}
		// On foot: a pilot near the heli base (infantry spawning there don't hold the helis)
		bNear = (HasPilotRole(PC, true) || HasPilotRole(PC, false)) && VSize(PC.Pawn.Location - HeliHome(H)) < 5000.0;
		if (bNear)
		{
			return true;
		}
	}
	return false;
}

/*-----------------------------------------------------------------------------
	Spawning into helicopters (as players can): dead bots respawn in a bot
	Huey waiting at base, or in a Huey/Bushranger flown by a human
-----------------------------------------------------------------------------*/

function bool BBWantsSpawnIns(ROVehicleHelicopter H)
{
	local BBAIController Pilot;

	if (PlayerController(H.Controller) != none)
	{
		return H.bTransportHelicopter || H.bIsGunship;
	}
	Pilot = BBAIController(H.Controller);
	return Pilot != none && H.bTransportHelicopter && Pilot.BBHeliMission == 'Lift' && Pilot.BBHeliTask == 'Wait';
}

function int BBFreeRideSeats(ROVehicleHelicopter H)
{
	local int i, N;

	for (i = 1; i < H.Seats.Length; i++)
	{
		if ((IsPassengerSeat(H, i) || IsDoorGunSeat(H, i)) && SeatFree(H, i))
		{
			N++;
		}
	}
	return N;
}

/** Points the spawn selection of dead bots at a heli that wants them (stock spawn code does the rest) */
function BBUpdateHeliSpawns()
{
	local int Team, i, Idx[2], Room[2];
	local ROTeamInfo ROTI;
	local ROVehicleHelicopter H;
	local BBAIController Bot;
	local ROPlayerReplicationInfo ROPRI;

	for (Team = 0; Team < 2; Team++)
	{
		Idx[Team] = -1;
		ROTI = ROTeamInfo(WorldInfo.GRI.Teams[Team]);
		if (ROTI == none)
		{
			continue;
		}
		for (i = 0; i < ArrayCount(ROTI.TeamHelicopterArray) && i < 10; i++)
		{
			H = ROTI.TeamHelicopterArray[i];
			if (HeliUsable(H) && H.CanSpawnInto() && BBWantsSpawnIns(H))
			{
				Idx[Team] = i;
				Room[Team] = BBFreeRideSeats(H);
				break;
			}
		}
	}

	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		ROPRI = ROPlayerReplicationInfo(Bot.PlayerReplicationInfo);
		if (ROPRI == none)
		{
			continue;
		}
		Team = Bot.GetTeamNum();
		if (Team < 2 && Idx[Team] >= 0 && Room[Team] > 0 && Bot.Pawn == none && Bot.BBCrewHeli == none &&
			ROPRI.RoleInfo != none && !ROPRI.RoleInfo.bIsPilot && !ROPRI.RoleInfo.bCanBeTankCrew)
		{
			if (!Bot.bBBHeliSpawnSel)
			{
				Bot.BBSavedSpawnSel = ROPRI.SpawnSelection;
				Bot.bBBHeliSpawnSel = true;
			}
			ROPRI.SpawnSelection = byte(110 + Idx[Team]);
			Room[Team]--;
		}
		else if (Bot.bBBHeliSpawnSel)
		{
			ROPRI.SpawnSelection = Bot.BBSavedSpawnSel;
			Bot.bBBHeliSpawnSel = false;
		}
	}
}

function bool BBPilotOnTheWay(ROVehicleHelicopter H)
{
	local BBAIController Bot;

	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		if (Bot.BBCrewHeli == H && Bot.BBCrewSeat == 0)
		{
			return true;
		}
	}
	return false;
}

function bool BBSeatClaimed(ROVehicleHelicopter H, int Seat)
{
	local BBAIController Bot;

	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		if (Bot.BBCrewHeli == H && Bot.BBCrewSeat == Seat)
		{
			return true;
		}
	}
	return false;
}

/** Bots we never pull out of the infantry fight */
function bool BBBotKeepsInfantryRole(BBAIController Bot)
{
	local ROPlayerReplicationInfo ROPRI;

	ROPRI = ROPlayerReplicationInfo(Bot.PlayerReplicationInfo);
	if (ROPRI == none || ROPRI.RoleInfo == none)
	{
		return true;
	}
	return ROPRI.RoleInfo.bIsTeamLeader || ROPRI.RoleInfo.bIsRadioman || ROPRI.RoleIndex == `ROLE_INDEX_SQUADLEADER;
}

function bool BBBotFreeForHeli(BBAIController Bot, byte Team)
{
	return Bot.GetTeamNum() == Team && Bot.BBCrewHeli == none && !Bot.bBBHeliPilot && !Bot.bBBHeliRider &&
		Vehicle(Bot.Pawn) == none && Bot.PlayerReplicationInfo != none && !Bot.bDeleteMe;
}

/**
 * Finds a bot for a heli seat: a bot already holding the right pilot role,
 * else one waiting to respawn (it will spawn at the pilot spawn), else one
 * walking near the heli and not fighting.
 */
function BBAIController BBPickCrewBot(ROVehicleHelicopter H, int Seat, bool bNeedsPilotRole)
{
	local BBAIController Bot, Best;
	local float Score, BestScore, Dist;
	local bool bHasRole, bAlive;

	BestScore = -1;
	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		if (!BBBotFreeForHeli(Bot, H.GetTeamNum()))
		{
			continue;
		}
		bHasRole = HasPilotRole(Bot, H.bTransportHelicopter);
		if (!bHasRole && BBBotKeepsInfantryRole(Bot))
		{
			continue;
		}
		if (!bNeedsPilotRole && HasPilotRole(Bot, true) == false && HasPilotRole(Bot, false))
		{
			// Pilots are kept for the cockpit
			continue;
		}

		bAlive = Bot.Pawn != none && Bot.Pawn.Health > 0;
		if (!bAlive && !bNeedsPilotRole)
		{
			// Infantry respawn far from the heli pad (they can spawn straight into a Huey instead)
			continue;
		}
		Dist = bAlive ? VSize(Bot.Pawn.Location - H.Location) : 0.0;
		if (bAlive && (Dist > BB_CrewPickupDist || (Bot.Enemy != none && Bot.LineOfSightTo(Bot.Enemy))))
		{
			continue;
		}

		Score = 1.0;
		if (bHasRole)
		{
			Score += 10.0;
		}
		if (!bAlive)
		{
			Score += 2.0;
		}
		else
		{
			Score += 1.0 - Dist / BB_CrewPickupDist;
		}
		Score += FRand() * 0.5;
		if (Score > BestScore)
		{
			BestScore = Score;
			Best = Bot;
		}
	}
	return Best;
}

function bool BBAssignCrew(ROVehicleHelicopter H, int Seat)
{
	local BBAIController Bot;
	local bool bNeedsPilotRole, bTransportRole;
	local class<RORoleInfo> RoleClass;

	if (BBSeatClaimed(H, Seat) || !SeatFree(H, Seat))
	{
		return false;
	}

	bNeedsPilotRole = (Seat == 0 || IsGunnerCopilotSeat(H, Seat));
	bTransportRole = H.bTransportHelicopter;
	Bot = BBPickCrewBot(H, Seat, bNeedsPilotRole);
	if (Bot == none)
	{
		return false;
	}

	if (bNeedsPilotRole && !HasPilotRole(Bot, bTransportRole))
	{
		// Never boot another bot (or human) out of the role: only free slots
		if (PilotSlotsFree(H.GetTeamNum(), bTransportRole) <= 0)
		{
			return false;
		}
		RoleClass = PilotRoleClass(H.GetTeamNum(), bTransportRole);
		if (RoleClass == none)
		{
			return false;
		}
		Bot.LeaveSquad();
		if (!ROPlayerReplicationInfo(Bot.PlayerReplicationInfo).SelectRoleByClass(Bot, RoleClass))
		{
			`log("[BetterBots][Heli] Could not give"@RoleClass@"to"@Bot.PlayerReplicationInfo.PlayerName);
			return false;
		}
	}

	Bot.BBSetCrewAssignment(H, Seat);
	`log("[BetterBots][Heli]"@Bot.PlayerReplicationInfo.PlayerName@"assigned to"@HeliName(H)@"seat"@Seat@
		((Bot.Pawn != none) ? "(boarding now)" : "(after respawn)"));
	return true;
}

/** Gunner copilot (Cobra/Bushranger) and door gunners */
function BBCrewGuns(ROVehicleHelicopter H, bool bAllPiloted)
{
	local int i;

	for (i = 1; i < H.Seats.Length; i++)
	{
		if (!SeatFree(H, i))
		{
			continue;
		}
		if (IsGunnerCopilotSeat(H, i))
		{
			// Uses a pilot slot: only once every heli has its pilot
			if (bAllPiloted && HeliOnGround(H) && PilotSlotsFree(H.GetTeamNum(), false) > 0)
			{
				BBAssignCrew(H, i);
			}
		}
		else if (IsDoorGunSeat(H, i) && HeliOnGround(H) && VSize(H.Location - HeliHome(H)) < 4000.0)
		{
			BBAssignCrew(H, i);
		}
	}
}

/*-----------------------------------------------------------------------------
	Passengers
-----------------------------------------------------------------------------*/

/** Distance from a point to the nearest objective that is still in play */
function float BBFrontDistance(vector P)
{
	local ROGameInfoTerritories ROGIT;
	local int i;
	local float D, Best;

	Best = 1000000.0;
	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none)
	{
		return Best;
	}
	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		if (ROGIT.Objectives[i] != none && ROGIT.Objectives[i].bActive)
		{
			D = VSize2D(ROGIT.Objectives[i].Location - P);
			Best = FMin(Best, D);
		}
	}
	return Best;
}

/** Active objective within Radius of the From-To segment (not the destination itself) */
function bool BBObjectiveOnRoute(vector From, vector To, float Radius, out vector ObjLoc)
{
	local ROGameInfoTerritories ROGIT;
	local int i;
	local vector Dir, P;
	local float Len, T, Best, D;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none)
	{
		return false;
	}
	Dir = To - From;
	Dir.Z = 0;
	Len = VSize(Dir);
	if (Len < 1.0)
	{
		return false;
	}
	Dir /= Len;
	Best = Radius;
	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		if (ROGIT.Objectives[i] == none || !ROGIT.Objectives[i].bActive || VSize2D(ROGIT.Objectives[i].Location - To) < Radius)
		{
			continue;
		}
		P = ROGIT.Objectives[i].Location - From;
		P.Z = 0;
		T = P dot Dir;
		if (T < 0 || T > Len)
		{
			continue;
		}
		D = VSize(P - Dir * T);
		if (D < Best)
		{
			Best = D;
			ObjLoc = ROGIT.Objectives[i].Location;
		}
	}
	return Best < Radius;
}

/** Heli sitting at its base, ready to take passengers */
function bool BBTakesPassengers(ROVehicleHelicopter H)
{
	local BBAIController Pilot;

	if (FreePassengerSeat(H) < 0 || !HeliOnGround(H) || VSize(H.Location - HeliHome(H)) > 4000.0)
	{
		return false;
	}
	if (BBFrontDistance(H.Location) < BB_FrontFarDist)
	{
		return false;
	}
	// Human pilots (Huey or Bushranger) take bots along
	if (PlayerController(H.Controller) != none)
	{
		return true;
	}
	// Bot transports while waiting at base
	Pilot = BBAIController(H.Controller);
	return Pilot != none && H.bTransportHelicopter && Pilot.BBHeliTask == 'Wait';
}

function BBBoardPassengers(ROVehicleHelicopter H)
{
	local BBAIController Bot, Best;
	local float DistSq, BestDistSq;
	local int Seat;

	if (WorldInfo.TimeSeconds < NextBoardTime || !BBTakesPassengers(H))
	{
		return;
	}

	BestDistSq = BB_CrewPickupDist * BB_CrewPickupDist;
	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		if (!BBBotFreeForHeli(Bot, H.GetTeamNum()) || Bot.Pawn == none || Bot.Pawn.Health <= 0 ||
			HasPilotRole(Bot, true) || HasPilotRole(Bot, false) || BBBotKeepsInfantryRole(Bot))
		{
			continue;
		}
		if (Bot.Enemy != none && Bot.LineOfSightTo(Bot.Enemy))
		{
			continue;
		}
		DistSq = VSizeSq(Bot.Pawn.Location - H.Location);
		if (DistSq < BestDistSq)
		{
			BestDistSq = DistSq;
			Best = Bot;
		}
	}
	if (Best == none)
	{
		return;
	}

	Seat = FreePassengerSeat(H);
	if (Seat >= 0)
	{
		// Claims the seat and walks over to it
		Best.BBSetCrewAssignment(H, Seat);
		NextBoardTime = WorldInfo.TimeSeconds + 1.0;
	}
}

/**
 * Should a passenger get off now? The heli is on the ground away from base,
 * close enough to the front (bot transports decide themselves, see BBHeliAI).
 */
function bool BBShouldUnload(ROVehicleHelicopter H)
{
	local BBAIController Pilot;

	if (H == none || !HeliOnGround(H) || VSize(H.Velocity) > 150.0)
	{
		return false;
	}
	Pilot = BBAIController(H.Controller);
	if (Pilot != none)
	{
		return Pilot.BBHeliTask == 'Unload' || Pilot.BBHeliTask == 'Bailout';
	}
	// Human pilot (or nobody flying): off when landed away from base near the fight
	return VSize(H.Location - HeliHome(H)) > 5000.0 && BBFrontDistance(H.Location) < BB_FrontFarDist * 1.3;
}

/*-----------------------------------------------------------------------------
	Human priority
-----------------------------------------------------------------------------*/

/** Human with the right pilot role next to a landed bot heli: the bot gets out */
function BBCheckHumanTakeover(ROVehicleHelicopter H)
{
	local PlayerController PC;
	local BBAIController Pilot;

	Pilot = BBAIController(H.Controller);
	if (Pilot == none || !HeliOnGround(H) || VSize(H.Velocity) > 100.0)
	{
		return;
	}
	foreach WorldInfo.AllControllers(class'PlayerController', PC)
	{
		if (PC.Pawn != none && PC.Pawn.Health > 0 && Vehicle(PC.Pawn) == none && PC.GetTeamNum() == H.GetTeamNum() &&
			HasPilotRole(PC, H.bTransportHelicopter) && VSize(PC.Pawn.Location - H.Location) < BB_HumanTakeDist)
		{
			PC.ClientMessage("[BetterBots]"@Pilot.PlayerReplicationInfo.PlayerName@"te deja el"@HeliName(H));
			Pilot.BBHeliGiveUp(true);
			return;
		}
	}
}

/**
 * The human picked a pilot role that bots fill. Returns true if a slot is
 * free now; otherwise a bot heli is on its way back and the request is
 * repeated once it lands.
 */
function bool BBRequestPilotRole(BBPlayerController PC, class<RORoleInfo> RoleClass, WeaponSelectionInfo Weapons,
	class<ROVehicle> Tank, bool bAllowTeamTank, bool bDesiredContext, bool bCloseMenu)
{
	local BBAIController Bot, BestGround, BestAir;
	local float D, BestGroundD, BestAirD;
	local bool bTransport;
	local ROVehicleHelicopter H;

	bTransport = RoleClass.default.bIsTransportPilot;
	BestGroundD = 1000000000.0;
	BestAirD = 1000000000.0;

	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		if (Bot.GetTeamNum() != PC.GetTeamNum() || !HasPilotRole(Bot, bTransport))
		{
			continue;
		}
		H = Bot.BBCurrentHeli();
		if (H == none || HeliOnGround(H))
		{
			// On foot, dead or sitting on the ground: free it right away
			D = (H != none) ? VSize(H.Location - HeliHome(H)) : 0.0;
			if (D < BestGroundD)
			{
				BestGroundD = D;
				BestGround = Bot;
			}
		}
		else if (Bot.bBBHeliPilot)
		{
			D = VSize(H.Location - HeliHome(H));
			if (D < BestAirD)
			{
				BestAirD = D;
				BestAir = Bot;
			}
		}
	}

	if (BestGround != none)
	{
		BestGround.BBHeliGiveUp(true);
		PC.ClientMessage("[BetterBots]"@BestGround.PlayerReplicationInfo.PlayerName@"te cede su plaza de piloto");
		return true;
	}
	if (BestAir != none)
	{
		CedePC = PC;
		CedeRoleClass = RoleClass;
		CedeWeapons = Weapons;
		CedeTank = Tank;
		bCedeAllowTeamTank = bAllowTeamTank;
		bCedeDesiredContext = bDesiredContext;
		bCedeCloseMenu = bCloseMenu;
		CedeBot = BestAir;
		CedeTime = WorldInfo.TimeSeconds;
		BestAir.BBHeliStartCede();
		PC.ClientMessage("[BetterBots]"@BestAir.PlayerReplicationInfo.PlayerName@"vuelve a base con el"@HeliName(BestAir.BBHeli)@
			"para cederte la plaza de piloto");
		return false;
	}
	return false;
}

/** Bot that was flying back to free a role has landed and left */
function BBCedeDone(BBAIController Bot)
{
	if (Bot != CedeBot || CedePC == none)
	{
		return;
	}
	CedePC.ClientMessage("[BetterBots] Plaza de piloto libre, el helicoptero te espera en base");
	CedeBot = none;
	CedePC.SelectRoleByClass(CedePC.GetTeamNum() == `ALLIES_TEAM_INDEX, CedeRoleClass, CedeWeapons, CedeTank,
		bCedeAllowTeamTank, bCedeDesiredContext, bCedeCloseMenu);
	CedePC = none;
}

function BBCheckCede()
{
	if (CedePC == none)
	{
		return;
	}
	// The bot died or it is taking too long: try again with whoever is free
	if (CedeBot == none || CedeBot.bDeleteMe || !CedeBot.BBIsFlyingHeli() || WorldInfo.TimeSeconds - CedeTime > 150.0)
	{
		CedeBot = none;
		if (PilotSlotsFree(CedePC.GetTeamNum(), CedeRoleClass.default.bIsTransportPilot) > 0 ||
			BBRequestPilotRole(CedePC, CedeRoleClass, CedeWeapons, CedeTank, bCedeAllowTeamTank, bCedeDesiredContext, bCedeCloseMenu))
		{
			CedePC.SelectRoleByClass(CedePC.GetTeamNum() == `ALLIES_TEAM_INDEX, CedeRoleClass, CedeWeapons, CedeTank,
				bCedeAllowTeamTank, bCedeDesiredContext, bCedeCloseMenu);
			CedePC = none;
		}
	}
}

/*-----------------------------------------------------------------------------
	Danger memory and Loach marks
-----------------------------------------------------------------------------*/

function BBExpireMemory()
{
	local int i;

	for (i = Threats.Length - 1; i >= 0; i--)
	{
		if (WorldInfo.TimeSeconds - Threats[i].Time > BB_ThreatLife)
		{
			Threats.Remove(i, 1);
		}
	}
	for (i = Strikes.Length - 1; i >= 0; i--)
	{
		if (WorldInfo.TimeSeconds - Strikes[i].Time > 40.0 || Strikes[i].P == none || Strikes[i].P.Health <= 0)
		{
			Strikes.Remove(i, 1);
		}
	}
	for (i = Marks.Length - 1; i >= 0; i--)
	{
		if (WorldInfo.TimeSeconds - Marks[i].Time > BB_MarkLife || Marks[i].P == none || Marks[i].P.Health <= 0)
		{
			Marks.Remove(i, 1);
		}
	}
}

/** A heli of Team was shot at from (or near) Loc */
function BBAddThreat(byte Team, vector Loc, float Amount)
{
	local int i;

	// Merge with a nearby spot
	for (i = 0; i < Threats.Length; i++)
	{
		if (Threats[i].Team == Team && VSizeSq(Threats[i].Loc - Loc) < 4000000.0)
		{
			Threats[i].Amount = FMin(Threats[i].Amount * BBFade(Threats[i].Time) + Amount, 1000.0);
			Threats[i].Time = WorldInfo.TimeSeconds;
			return;
		}
	}
	i = Threats.Length;
	Threats.Length = i + 1;
	Threats[i].Loc = Loc;
	Threats[i].Amount = Amount;
	Threats[i].Time = WorldInfo.TimeSeconds;
	Threats[i].Team = Team;
	`log("[BetterBots][Heli] New danger spot for team"@Team@"at"@Loc@"amount"@int(Amount));
}

function float BBFade(float Time)
{
	return FMax(0.0, 1.0 - (WorldInfo.TimeSeconds - Time) / BB_ThreatLife);
}

/** Remembered danger for Team's helis around Loc (0 = none, ~100 = a few hits) */
function float BBDanger(byte Team, vector Loc, float Radius)
{
	local int i;
	local float Sum, D;

	for (i = 0; i < Threats.Length; i++)
	{
		if (Threats[i].Team == Team)
		{
			D = VSize2D(Threats[i].Loc - Loc);
			if (D < Radius)
			{
				Sum += Threats[i].Amount * BBFade(Threats[i].Time) * (1.0 - 0.5 * D / Radius);
			}
		}
	}
	return Sum;
}

/** Nearest remembered danger spot to a segment, for route detours */
function bool BBDangerOnRoute(byte Team, vector From, vector To, float Radius, float MinAmount, out vector DangerLoc)
{
	local int i;
	local vector Dir;
	local float Len, T, BestAmount, A;
	local vector P;

	Dir = To - From;
	Dir.Z = 0;
	Len = VSize(Dir);
	if (Len < 1.0)
	{
		return false;
	}
	Dir /= Len;
	for (i = 0; i < Threats.Length; i++)
	{
		if (Threats[i].Team != Team)
		{
			continue;
		}
		A = Threats[i].Amount * BBFade(Threats[i].Time);
		if (A < MinAmount)
		{
			continue;
		}
		P = Threats[i].Loc - From;
		P.Z = 0;
		T = P dot Dir;
		if (T < 0 || T > Len)
		{
			continue;
		}
		if (VSize(P - Dir * T) < Radius && A > BestAmount)
		{
			BestAmount = A;
			DangerLoc = Threats[i].Loc;
		}
	}
	return BestAmount > 0;
}

function BBAddMark(byte Team, Pawn P)
{
	local int i;

	for (i = 0; i < Marks.Length; i++)
	{
		if (Marks[i].P == P)
		{
			Marks[i].Loc = P.Location;
			Marks[i].Time = WorldInfo.TimeSeconds;
			return;
		}
	}
	i = Marks.Length;
	Marks.Length = i + 1;
	Marks[i].P = P;
	Marks[i].Loc = P.Location;
	Marks[i].Time = WorldInfo.TimeSeconds;
	Marks[i].Team = Team;
}

/**
 * A heli of Caller's team is being shot by Shooter: attack helis (bot or
 * human, who gets a message) should go after it.
 */
function BBRequestStrike(ROVehicleHelicopter Caller, Pawn Shooter)
{
	local int i;
	local PlayerController PC;
	local ROVehicleHelicopter H;
	local byte Team;

	Team = Caller.GetTeamNum();
	for (i = 0; i < Strikes.Length; i++)
	{
		if (Strikes[i].P == Shooter && Strikes[i].Team == Team)
		{
			Strikes[i].Time = WorldInfo.TimeSeconds;
			return;
		}
	}
	i = Strikes.Length;
	Strikes.Length = i + 1;
	Strikes[i].P = Shooter;
	Strikes[i].Time = WorldInfo.TimeSeconds;
	Strikes[i].Team = Team;
	Strikes[i].Caller = Caller;
	`log("[BetterBots][Heli]"@HeliName(Caller)@"under fire from"@Shooter@"- calling the attack helis");

	// Humans flying an attack heli get the call too
	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', H)
	{
		PC = PlayerController(H.Controller);
		if (PC != none && H != Caller && H.GetTeamNum() == Team && !H.bTransportHelicopter)
		{
			PC.ClientMessage("[BetterBots]"@HeliName(Caller)@"bajo fuego: tirador marcado en el mapa");
		}
	}
}

/** Takes the newest strike call this heli can answer (in range, visible, no friendlies there) */
function Pawn BBTakeStrike(ROVehicleHelicopter H, float Range)
{
	local int i;
	local Pawn P;

	for (i = Strikes.Length - 1; i >= 0; i--)
	{
		P = Strikes[i].P;
		if (Strikes[i].Team != H.GetTeamNum() || Strikes[i].Caller == H || P == none || P.Health <= 0)
		{
			continue;
		}
		if (VSize(P.Location - H.Location) > Range || !FastTrace(P.Location + vect(0,0,40), H.Location - vect(0,0,150)) ||
			BBFriendliesNear(H.GetTeamNum(), P.Location, 2500.0))
		{
			continue;
		}
		Strikes.Remove(i, 1);
		return P;
	}
	return none;
}

function bool BBIsMarked(byte Team, Pawn P)
{
	local int i;

	for (i = 0; i < Marks.Length; i++)
	{
		if (Marks[i].P == P && Marks[i].Team == Team)
		{
			return true;
		}
	}
	return false;
}

/*-----------------------------------------------------------------------------
	Targets and landing zones
-----------------------------------------------------------------------------*/

function bool BBFriendliesNear(byte Team, vector Loc, float Radius)
{
	local Pawn P;

	foreach WorldInfo.AllPawns(class'Pawn', P)
	{
		if (P.Health > 0 && P.GetTeamNum() == Team && ROVehicleHelicopter(P) == none && ROHelicopterWeaponPawn(P) == none &&
			VSizeSq(P.Location - Loc) < Radius * Radius)
		{
			return true;
		}
	}
	return false;
}

/** Objective being captured, used as a target priority */
function bool BBInCapturingObjective(Pawn P)
{
	local ROGameInfoTerritories ROGIT;
	local int i;
	local ROObjective Obj;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none)
	{
		return false;
	}
	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		Obj = ROGIT.Objectives[i];
		if (Obj != none && Obj.bActive && Obj.bCapping && Obj.CapTeamIndex == P.GetTeamNum() &&
			VSize2D(Obj.Location - P.Location) < 2500.0)
		{
			return true;
		}
	}
	return false;
}

/** Anti-aircraft capable: fixed weapons, machine gunners, rocket men */
function bool BBIsAirThreat(Pawn P)
{
	local ROPlayerReplicationInfo ROPRI;

	if (Vehicle(P) != none)
	{
		return true;
	}
	ROPRI = (P.Controller != none) ? ROPlayerReplicationInfo(P.Controller.PlayerReplicationInfo) : none;
	if (ROPRI != none && ROPRI.RoleInfo != none && ROPRI.RoleInfo.RoleType == RORIT_MachineGunner)
	{
		return true;
	}
	return ROWeapon(P.Weapon) != none && ROWeapon(P.Weapon).WeaponClassType == ROWCT_ATRocket;
}

/**
 * Best ground target for an attacking heli. Priority: anti-aircraft > enemies
 * capturing > Loach marks > anything else. Never near friendlies (50 m).
 */
function Pawn BBPickAirTarget(ROVehicleHelicopter H, vector Center, float CenterRadius, float MaxRange)
{
	local Pawn P, Best;
	local float Score, BestScore, D;
	local byte Team;
	local vector Eye;

	Team = H.GetTeamNum();
	Eye = H.Location - vect(0,0,150);
	BestScore = -100000.0;
	foreach WorldInfo.AllPawns(class'Pawn', P)
	{
		if (P.Health <= 0 || P.GetTeamNum() == Team || P.GetTeamNum() > 1 || ROVehicleHelicopter(P) != none ||
			P.Controller == none || P.DrivenVehicle != none)
		{
			continue;
		}
		D = VSize(P.Location - H.Location);
		if (D > MaxRange || VSize2D(P.Location - Center) > CenterRadius)
		{
			continue;
		}
		if (!FastTrace(P.Location + vect(0,0,40), Eye))
		{
			continue;
		}
		if (BBFriendliesNear(Team, P.Location, 2500.0))
		{
			continue;
		}

		Score = -D / 200.0;
		if (BBIsAirThreat(P))
		{
			Score += 400.0;
		}
		if (BBInCapturingObjective(P))
		{
			Score += 250.0;
		}
		if (BBIsMarked(Team, P))
		{
			Score += 150.0;
		}
		if (Score > BestScore)
		{
			BestScore = Score;
			Best = P;
		}
	}
	return Best;
}

/** Where the team's helis should fight: the objective that needs help most */
function bool BBFightCenter(byte Team, out vector Center)
{
	local ROGameInfoTerritories ROGIT;
	local ROObjective Obj;
	local int i;
	local float Score, BestScore;
	local bool bFound;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none)
	{
		return false;
	}
	BestScore = -1000000.0;
	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		Obj = ROGIT.Objectives[i];
		if (Obj == none || !Obj.bActive)
		{
			continue;
		}
		Score = 0;
		if (Obj.ObjState != Team)
		{
			Score += 300.0;		// Enemy or neutral: attack it
		}
		else if (Obj.bCapping && Obj.CapTeamIndex != Team)
		{
			Score += 500.0 + 500.0 * Obj.CapProgress;	// Ours, being taken
		}
		Score += FRand() * 50.0;
		if (Score > BestScore)
		{
			BestScore = Score;
			Center = Obj.Location;
			bFound = true;
		}
	}
	return bFound;
}

function float BBGroundZ(vector P, out vector HitNormal, out Actor HitActor)
{
	local vector HitLocation, Start, End;

	Start = P;
	Start.Z += 20000.0;
	End = P;
	End.Z -= 60000.0;
	// Water stops the trace too (a heli can't land on it)
	foreach TraceActors(class'Actor', HitActor, HitLocation, HitNormal, End, Start,,, TRACEFLAG_PhysicsVolumes)
	{
		if (HitActor.bWorldGeometry || Pawn(HitActor) != none || HitActor.bBlockActors ||
			(PhysicsVolume(HitActor) != none && PhysicsVolume(HitActor).bWaterVolume))
		{
			return HitLocation.Z;
		}
	}
	HitActor = none;
	return End.Z;
}

/** Flat, open ground for a heli (no trees, walls or slopes within ~12 m) */
function bool BBIsLandable(vector P, out vector LandPoint)
{
	local vector N, Offset;
	local Actor A;
	local float Z0, Z;
	local int i;

	Z0 = BBGroundZ(P, N, A);
	if (A == none || Pawn(A) != none || N.Z < 0.94 || PhysicsVolume(A) != none)
	{
		return false;
	}
	for (i = 0; i < 6; i++)
	{
		Offset.X = Cos(i * 1.0472) * 650.0;
		Offset.Y = Sin(i * 1.0472) * 650.0;
		Z = BBGroundZ(P + Offset, N, A);
		if (A == none || Pawn(A) != none || Abs(Z - Z0) > 140.0 || N.Z < 0.88)
		{
			return false;
		}
		// Wider ring: a big drop means we are on a roof or a ledge
		Z = BBGroundZ(P + Offset * 2.0, N, A);
		if (A == none || Abs(Z - Z0) > 400.0)
		{
			return false;
		}
	}
	LandPoint = P;
	LandPoint.Z = Z0;
	return true;
}

/**
 * Landing zone for a transport: 150-300 m from the fight on our side,
 * further away the more danger is remembered there (plus ExtraDist after an
 * aborted landing). Varies the angle so drops are not predictable.
 */
function bool BBPickLZ(ROVehicleHelicopter H, float ExtraDist, out vector LZ)
{
	local vector Center, Home, Dir, Cand, Land, BestLand;
	local float BaseDist, MaxDist, D, Ang, Danger, Score, BestScore;
	local int i;
	local byte Team;

	Team = H.GetTeamNum();
	if (!BBFightCenter(Team, Center))
	{
		return false;
	}
	Home = HeliHome(H);
	Dir = Home - Center;
	Dir.Z = 0;
	MaxDist = VSize(Dir) * 0.85;
	Dir = Normal(Dir);

	Danger = BBDanger(Team, Center, 15000.0);
	BaseDist = 7500.0 + FRand() * 7500.0 + FMin(Danger * 60.0, 10000.0) + ExtraDist;
	BaseDist = FMin(BaseDist, FMax(MaxDist, 5000.0));

	BestScore = -1000000.0;
	for (i = 0; i < 24; i++)
	{
		Ang = (FRand() - 0.5) * 1.6;	// +-46 deg from the line to our base
		D = BaseDist * (0.8 + 0.4 * FRand());
		Cand = Center + (Dir * Cos(Ang) + (vect(0,0,1) cross Dir) * Sin(Ang)) * D;
		if (!BBIsLandable(Cand, Land))
		{
			continue;
		}
		Score = -BBDanger(Team, Land, 6000.0) * 20.0 - Abs(D - BaseDist) / 100.0 + FRand() * 30.0;
		if (Score > BestScore)
		{
			BestScore = Score;
			BestLand = Land;
		}
	}
	if (BestScore <= -1000000.0)
	{
		`log("[BetterBots][Heli] No landable LZ found near"@Center);
		return false;
	}
	LZ = BestLand;
	return true;
}

/*-----------------------------------------------------------------------------
	Debug drawing (BBHeliDebug)
-----------------------------------------------------------------------------*/

function BBToggleDebug(PlayerController PC)
{
	bDebugDraw = !bDebugDraw;
	if (bDebugDraw)
	{
		SetTimer(0.5, true, 'BBDebugTick');
		PC.ClientMessage("[BetterBots] Depuracion de helicopteros ACTIVADA (BBHeliDebug para quitar)");
		PC.ClientMessage("[BetterBots] Verde=ruta  Azul=base  Amarillo=LZ  Rojo=blanco/peligro  Cian=espera Cobra  Naranja=marcas  Blanco=deteccion obstaculos");
	}
	else
	{
		ClearTimer('BBDebugTick');
		FlushPersistentDebugLines();
		PC.ClientMessage("[BetterBots] Depuracion de helicopteros desactivada");
	}
}

function BBDebugTick()
{
	local BBAIController Bot;
	local ROVehicleHelicopter H;
	local PlayerController PC;
	local int i;
	local bool bText;
	local string S;

	FlushPersistentDebugLines();
	bText = WorldInfo.TimeSeconds > NextDebugText;
	if (bText)
	{
		NextDebugText = WorldInfo.TimeSeconds + 5.0;
		foreach WorldInfo.AllControllers(class'PlayerController', PC)
		{
			break;
		}
	}

	foreach WorldInfo.AllControllers(class'BBAIController', Bot)
	{
		if (!Bot.BBIsFlyingHeli())
		{
			continue;
		}
		H = Bot.BBHeli;
		// Where the autopilot is going
		if (Bot.BBNavMode == 3)
		{
			DrawDebugLine(H.Location, H.Location + Bot.BBNavVel * 2.0, 0, 255, 0, true);
		}
		else if (Bot.BBNavMode != 0)
		{
			DrawDebugLine(H.Location, Bot.BBNavPoint, 0, 255, 0, true);
		}
		// Obstacle look-ahead (2.5 s of flight)
		DrawDebugLine(H.Location, H.Location + H.Velocity * 2.5 - vect(0,0,200), 255, 255, 255, true);
		DrawDebugLine(H.Location, Bot.BBHeliHome, 0, 0, 255, true);
		if (Bot.BBHeliLZ != vect(0,0,0))
		{
			DrawDebugLine(H.Location, Bot.BBHeliLZ, 255, 255, 0, true);
			DrawDebugSphere(Bot.BBHeliLZ, 650.0, 12, 255, 255, 0, true);
		}
		if (Bot.BBHeliTask == 'RunIn')
		{
			DrawDebugLine(H.Location, Bot.BBHeliTargetLoc, 255, 0, 0, true);
		}
		if (Bot.BBHeliMission == 'Attack')
		{
			DrawDebugSphere(Bot.BBHeliStandoff, 1800.0, 12, 0, 255, 255, true);
		}
		if (bText && PC != none)
		{
			S = Bot.PlayerReplicationInfo.PlayerName@HeliName(H)@Bot.BBHeliTask@"alt"@int(Bot.BBHeliAGL() / 50.0)$"m vel"@
				int(VSize(H.Velocity) * 0.072)$"km/h HP"@H.Health;
			if (Bot.BBHeliTask == 'RunIn')
			{
				S = S@(Bot.bBBHeliLongShot ? "(tiro lejano)" : "(pasada)");
			}
			PC.ClientMessage("[Heli]"@S);
		}
	}
	for (i = 0; i < Threats.Length; i++)
	{
		DrawDebugSphere(Threats[i].Loc, 300.0 + FMin(Threats[i].Amount, 100.0) * 20.0 * BBFade(Threats[i].Time), 8, 255, 0, 0, true);
	}
	for (i = 0; i < Marks.Length; i++)
	{
		if (Marks[i].P != none)
		{
			DrawDebugSphere(Marks[i].P.Location, 80.0, 6, 255, 128, 0, true);
		}
	}
}

defaultproperties
{
	HumanSpawnTime=-1
}
