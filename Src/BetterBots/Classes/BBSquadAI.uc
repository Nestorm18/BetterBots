//=============================================================================
// BBSquadAI
//=============================================================================
// Bot controller layer between the helicopter code (BBHeliAI) and the
// infantry code (BBAIController):
//
// 1. Commander abilities. The stock state walks the commander to a radio
//    first (the North has none, so the NVA commander never calls anything)
//    and picks an ability at random. Here the commander decides by itself,
//    at key moments:
//    - Artillery / napalm / gunship on groups of 3+ enemies some teammate
//      can see, near an objective in play, with at most 2 friendlies
//      within 30 m. US needs a radioman next to him or a radio nearby.
//    - North: ambush (instant respawn) when many are waiting to respawn and
//      a point is in combat; Ho Chi Minh trail when attacking or after
//      losing a point; anti-air only with enemy helicopters in the air.
// 2. Fixed machine guns (DShK / M2). Defenders near one man it when the
//    enemy is close or helicopters are around; they leave when flanked,
//    when the point falls, when a human walks up to it, or after a minute
//    without targets.
//=============================================================================

class BBSquadAI extends BBHeliAI
	config(Game);

const BB_CmdTick			= 3.0;
const BB_StrikeRadius		= 1500.0;	// Allies counted within 30 m of an impact point
const BB_StrikeMaxAllies	= 2;
const BB_TurretUseDist		= 2000.0;	// Defenders within 40 m of a fixed MG may take it
const BB_TurretRange		= 9000.0;

// Commander
var		float		BBCmdNextCall;
var		float		BBCmdReadySince[4];		// When each ability became ready (0 = not ready)
var		int			BBCmdLastOwned;
var		float		BBCmdLostPointTime;

// Fixed MGs
var		ROTurret	BBTurret;				// The one we are walking to or manning
var		bool		bBBTurretUser;			// Read by Possess
var		float		BBTurretApproachStart;
var		float		BBTurretNextUse;
var		float		BBTurretLastTarget;
var		Pawn		BBTurretTarget;
var		float		BBTurretNextPick;
var		float		BBTurretBurstEnd;
var		float		BBTurretNextBurst;
var		bool		bBBTurretFiring;
var		float		BBTurretManStart;

event PostBeginPlay()
{
	super.PostBeginPlay();
	BBCmdLastOwned = -1;
	SetTimer(BB_CmdTick + FRand(), true, 'BBCommanderTick');
}

/*-----------------------------------------------------------------------------
	Hooks for BBAIController (objective knowledge lives there)
-----------------------------------------------------------------------------*/

/** True while this bot's objective is ours and it is defending it */
function bool BBDefendingObjective(out ROObjective Obj)
{
	return false;
}

/** The team is attacking (not the defending side in Territories) */
function bool BBTeamAttacking()
{
	return true;
}

/** This bot may leave what it is doing to man a fixed MG */
function bool BBMayManTurret()
{
	return true;
}

/*-----------------------------------------------------------------------------
	Commander
-----------------------------------------------------------------------------*/

/** The stock "walk to a radio and pick at random" is replaced by BBCommanderTick */
function bool ShouldCallInAbility(optional int PercentageThreshold = 101)
{
	return false;
}

function bool BBIsCommander()
{
	local ROPlayerReplicationInfo ROPRI;

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	return ROPRI != none && ROPRI.RoleInfo != none && ROPRI.RoleInfo.bIsTeamLeader;
}

/** Ability "slot" ready: 1, 2, 3 = NextAbilityOne/Two/ThreeTime, 0 = North ambush */
function bool BBCmdReady(int Slot)
{
	local ROGameReplicationInfo ROGRI;
	local int T, RT;

	ROGRI = ROGameReplicationInfo(WorldInfo.GRI);
	if (ROGRI == none)
	{
		return false;
	}
	T = GetTeamNum();
	RT = WorldInfo.GRI.RemainingTime;
	switch (Slot)
	{
		case 0: return ROGRI.NextInstantRespawn[T] >= RT;
		case 1: return ROGRI.NextAbilityOneTime[T] >= RT;
		case 2: return ROGRI.NextAbilityTwoTime[T] >= RT;
		case 3: return ROGRI.NextAbilityThreeTime[T] >= RT;
	}
	return false;
}

/** Seconds an ability has been ready and unused */
function float BBCmdWaiting(int Slot)
{
	if (!BBCmdReady(Slot))
	{
		BBCmdReadySince[Slot] = 0;
		return 0;
	}
	if (BBCmdReadySince[Slot] == 0)
	{
		BBCmdReadySince[Slot] = WorldInfo.TimeSeconds;
	}
	return WorldInfo.TimeSeconds - BBCmdReadySince[Slot];
}

/** US radio access: a radioman next to us or a fixed radio nearby */
function bool BBCmdHasRadio()
{
	local ROTeamInfo ROTI;
	local Controller C;
	local ROPlayerReplicationInfo PRI;
	local int i;

	if (GetTeamNum() == `AXIS_TEAM_INDEX)
	{
		return true;
	}
	foreach WorldInfo.AllControllers(class'Controller', C)
	{
		PRI = ROPlayerReplicationInfo(C.PlayerReplicationInfo);
		if (C != self && C.Pawn != none && C.Pawn.Health > 0 && C.GetTeamNum() == GetTeamNum() && PRI != none &&
			PRI.RoleInfo != none && PRI.RoleInfo.bIsRadioman && VSizeSq(C.Pawn.Location - Pawn.Location) < 1000000.0)	// 20 m
		{
			return true;
		}
	}
	ROTI = ROTeamInfo(PlayerReplicationInfo.Team);
	if (ROTI != none)
	{
		for (i = 0; i < `MAX_RADIOS; i++)
		{
			if (ROTI.Radios[i] != none && ROTI.Radios[i].bAvailable && VSizeSq(ROTI.Radios[i].Location - Pawn.Location) < 2250000.0)	// 30 m
			{
				return true;
			}
		}
	}
	return false;
}

/** Some teammate has a line of sight to this enemy */
function bool BBTeamSees(Pawn Target)
{
	local Controller C;
	local vector EnemyEye;

	EnemyEye = Target.Location + vect(0,0,40);
	foreach WorldInfo.AllControllers(class'Controller', C)
	{
		if (C.Pawn != none && C.Pawn.Health > 0 && C.GetTeamNum() == GetTeamNum() && Vehicle(C.Pawn) == none &&
			VSizeSq(C.Pawn.Location - Target.Location) < 100000000.0 &&	// 200 m
			FastTrace(EnemyEye, C.Pawn.Location + vect(0,0,50)))
		{
			return true;
		}
	}
	return false;
}

function float BBDistToActiveObjective(vector P)
{
	local ROGameInfoTerritories ROGIT;
	local int i;
	local float Best;

	Best = 1000000.0;
	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT != none)
	{
		for (i = 0; i < ROGIT.Objectives.Length; i++)
		{
			if (ROGIT.Objectives[i] != none && ROGIT.Objectives[i].bActive)
			{
				Best = FMin(Best, VSize2D(ROGIT.Objectives[i].Location - P));
			}
		}
	}
	return Best;
}

/**
 * Best impact point: the seen enemy with most enemies around it (within
 * 25 m), near an objective in play, with few friendlies close.
 */
function bool BBCmdFindCluster(out vector Loc, out int Size)
{
	local Pawn E, O, F;
	local int N, NumAllies;
	local int BestN;
	local vector BestLoc;

	foreach WorldInfo.AllPawns(class'Pawn', E)
	{
		if (E.Health <= 0 || E.GetTeamNum() == GetTeamNum() || E.GetTeamNum() > 1 || Vehicle(E) != none ||
			E.Controller == none || BBDistToActiveObjective(E.Location) > 6000.0)
		{
			continue;
		}
		N = 0;
		foreach WorldInfo.AllPawns(class'Pawn', O)
		{
			if (O.Health > 0 && O.GetTeamNum() == E.GetTeamNum() && Vehicle(O) == none && VSizeSq(O.Location - E.Location) < 1562500.0)	// 25 m
			{
				N++;
			}
		}
		if (N <= BestN || N < 2)
		{
			continue;
		}
		NumAllies = 0;
		foreach WorldInfo.AllPawns(class'Pawn', F)
		{
			if (F.Health > 0 && F.GetTeamNum() == GetTeamNum() && VSizeSq(F.Location - E.Location) < BB_StrikeRadius * BB_StrikeRadius)
			{
				NumAllies++;
			}
		}
		if (NumAllies > BB_StrikeMaxAllies || !BBTeamSees(E))
		{
			continue;
		}
		BestN = N;
		BestLoc = E.Location;
	}
	Size = BestN;
	Loc = BestLoc;
	return BestN >= 2;
}

function bool BBEnemyHeliFlying()
{
	local ROVehicleHelicopter H;

	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', H)
	{
		if (H.Health > 0 && H.GetTeamNum() != GetTeamNum() && H.GetTeamNum() < 2 && H.Controller != none &&
			!H.bVehicleOnGround && !H.bWasChassisTouchingGroundLastTick)
		{
			return true;
		}
	}
	return false;
}

/** Our team lost an objective in the last minute */
function bool BBCmdLostPointRecently()
{
	local ROGameInfoTerritories ROGIT;
	local int i, N;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none)
	{
		return false;
	}
	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		if (ROGIT.Objectives[i] != none && ROGIT.Objectives[i].ObjState == GetTeamNum())
		{
			N++;
		}
	}
	if (BBCmdLastOwned >= 0 && N < BBCmdLastOwned)
	{
		BBCmdLostPointTime = WorldInfo.TimeSeconds;
	}
	BBCmdLastOwned = N;
	return BBCmdLostPointTime > 0 && WorldInfo.TimeSeconds - BBCmdLostPointTime < 60.0;
}

function bool BBPointInCombat()
{
	local ROGameInfoTerritories ROGIT;
	local int i;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none)
	{
		return false;
	}
	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		if (ROGIT.Objectives[i] != none && ROGIT.Objectives[i].bActive && ROGIT.Objectives[i].bCapping)
		{
			return true;
		}
	}
	return false;
}

function int BBNumTeamDead()
{
	local Controller C;
	local int N;

	foreach WorldInfo.AllControllers(class'Controller', C)
	{
		if (C.GetTeamNum() == GetTeamNum() && C.PlayerReplicationInfo != none && !C.PlayerReplicationInfo.bOnlySpectator &&
			(C.Pawn == none || C.Pawn.Health <= 0))
		{
			N++;
		}
	}
	return N;
}

/** Aim a strike: SavedArtilleryCoords is what the stock AICall* functions use */
function BBCmdAimAt(vector Loc)
{
	local ROTeamInfo ROTI;

	ROTI = ROTeamInfo(PlayerReplicationInfo.Team);
	if (ROTI != none)
	{
		ROTI.SavedArtilleryCoords = Loc;
	}
}

function BBCmdCalled(string What, optional vector Loc, optional int Size)
{
	BBCmdNextCall = WorldInfo.TimeSeconds + 30.0 + FRand() * 15.0;
	`log("[BetterBots] Commander"@BBName()@"(team"@GetTeamNum()$") called"@What@
		((Size > 0) ? "on"@Size@"enemies at"@Loc : ""));
}

function BBCommanderTick()
{
	if (!BBIsCommander() || Pawn == none || Pawn.Health <= 0 || Vehicle(Pawn) != none || !IsTerritoriesGame())
	{
		return;
	}
	BBCmdLostPointRecently();	// Keeps the owned-points count up to date
	if (WorldInfo.TimeSeconds < BBCmdNextCall)
	{
		return;
	}
	if (GetTeamNum() == `AXIS_TEAM_INDEX)
	{
		BBCmdNorth();
	}
	else
	{
		BBCmdSouth();
	}
}

function BBCmdNorth()
{
	local ROGameReplicationInfo ROGRI;
	local vector Loc;
	local int Size, MinSize;

	ROGRI = ROGameReplicationInfo(WorldInfo.GRI);

	// Anti-air only when an enemy heli is up
	if (BBCmdReady(3) && ROGRI.bAntiAirAvailable[GetTeamNum()] != 0 && BBEnemyHeliFlying())
	{
		if (AIEnableAntiAir())
		{
			BBCmdCalled("anti-air");
			return;
		}
	}

	// Ambush: many waiting to respawn and a point being fought over
	if (BBCmdReady(0) && BBNumTeamDead() >= 6 && BBPointInCombat())
	{
		if (AIAmbushRespawn())
		{
			BBCmdCalled("ambush respawn");
			return;
		}
	}

	// Ho Chi Minh trail when attacking or right after losing a point
	if (BBCmdReady(1) && (BBTeamAttacking() || BBCmdLostPointRecently()))
	{
		if (AIHoChiMinhTrail() && ROGameInfo(WorldInfo.Game).bEnableEnhancedLogistics)
		{
			BBCmdCalled("Ho Chi Minh trail");
			return;
		}
	}

	// Barrage on a seen group (2 is enough once it has waited 2 minutes)
	MinSize = (BBCmdWaiting(2) > 120.0) ? 2 : 3;
	if (BBCmdReady(2) && ROGRI.bArtilleryAvailable[GetTeamNum()] != 0 && BBCmdFindCluster(Loc, Size) && Size >= MinSize)
	{
		BBCmdAimAt(Loc);
		if (AICallArtyStrike())
		{
			BBCmdCalled("artillery", Loc, Size);
		}
	}
}

function BBCmdSouth()
{
	local ROGameReplicationInfo ROGRI;
	local ROMapInfo ROMI;
	local vector Loc;
	local int Size, Slack;

	ROGRI = ROGameReplicationInfo(WorldInfo.GRI);
	if (ROGRI.bArtilleryAvailable[GetTeamNum()] == 0 || !(BBCmdReady(1) || BBCmdReady(2) || BBCmdReady(3)))
	{
		return;
	}
	if (!BBCmdHasRadio() || !BBCmdFindCluster(Loc, Size))
	{
		return;
	}
	// Don't sit on abilities: after 2 minutes a smaller group will do
	Slack = (FMax(FMax(BBCmdWaiting(1), BBCmdWaiting(2)), BBCmdWaiting(3)) > 120.0) ? 1 : 0;

	BBCmdAimAt(Loc);
	if (BBCmdReady(3) && Size >= 5 - Slack)
	{
		if (AICallNapalmStrike())
		{
			BBCmdCalled("napalm", Loc, Size);
			return;
		}
	}
	if (BBCmdReady(1) && Size >= 4 - Slack)
	{
		ROMI = ROMapInfo(WorldInfo.GetMapInfo());
		if ((ROMI != none && ROMI.SouthernForce == SFOR_AusArmy) ? AICallBombingRun() : AICallGunshipStrike())
		{
			BBCmdCalled("gunship/bombing run", Loc, Size);
			return;
		}
	}
	if (BBCmdReady(2) && Size >= 3 - Slack)
	{
		if (AICallArtyStrike())
		{
			BBCmdCalled("artillery", Loc, Size);
		}
	}
}

/*-----------------------------------------------------------------------------
	Fixed machine guns
-----------------------------------------------------------------------------*/

function bool BBTurretClaimed(ROTurret T)
{
	local BBSquadAI Bot;

	foreach WorldInfo.AllControllers(class'BBSquadAI', Bot)
	{
		if (Bot != self && Bot.BBTurret == T)
		{
			return true;
		}
	}
	return false;
}

function bool BBTurretUsable(ROTurret T)
{
	return T != none && !T.bDeleteMe && T.Health > 0 && T.Driver == none && T.IsOwnedByTeam(Pawn) &&
		T.MyWeapon != none && T.MyWeapon.HasAnyAmmo();
}

/** Enemy close enough to justify manning a gun: seen recently, or an enemy heli about */
function bool BBTurretWanted()
{
	if (Enemy != none && LineOfSightTo(Enemy))
	{
		return true;
	}
	if (LastSightTime > 0 && WorldInfo.TimeSeconds - LastSightTime < 10.0)
	{
		return true;
	}
	return BBEnemyHeliFlying();
}

/**
 * Called from the combat tick. Walks to a free fixed MG near the defended
 * objective and gets on it. Returns true while busy with it.
 */
function bool BBTryUseTurret()
{
	local ROTurret T, Best;
	local ROObjective Obj;
	local float D, BestD;
	local ROPlayerReplicationInfo ROPRI;

	if (Pawn == none || Vehicle(Pawn) != none)
	{
		return false;
	}

	// On the way to one
	if (BBTurret != none)
	{
		if (!BBTurretUsable(BBTurret) || WorldInfo.TimeSeconds - BBTurretApproachStart > 20.0)
		{
			BBTurret = none;
			BBTurretNextUse = WorldInfo.TimeSeconds + 20.0;
			return false;
		}
		if (VSize(BBTurret.Location - Pawn.Location) < 320.0)
		{
			Pawn.ShouldCrouch(false);
			Pawn.ShouldProne(false);
			bBBTurretUser = true;
			if (!BBTurret.DriverEnter(Pawn))
			{
				bBBTurretUser = false;
				BBTurret = none;
				BBTurretNextUse = WorldInfo.TimeSeconds + 20.0;
				return false;
			}
			`log("[BetterBots]"@BBName()@"manning fixed MG"@BBTurret);
		}
		return true;
	}

	if (WorldInfo.TimeSeconds < BBTurretNextUse || !BBMayManTurret() || !BBDefendingObjective(Obj) || !BBTurretWanted())
	{
		return false;
	}
	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || ROPRI.RoleInfo == none || !(ROPRI.RoleInfo.RoleType == RORIT_MachineGunner || ROPRI.RoleInfo.RoleType == RORIT_Rifleman))
	{
		return false;
	}

	BestD = BB_TurretUseDist;
	foreach WorldInfo.DynamicActors(class'ROTurret', T)
	{
		if (!BBTurretUsable(T) || BBTurretClaimed(T) || VSize2D(T.Location - Obj.Location) > 4000.0)
		{
			continue;
		}
		D = VSize(T.Location - Pawn.Location);
		if (D < BestD)
		{
			BestD = D;
			Best = T;
		}
	}
	if (Best == none)
	{
		BBTurretNextUse = WorldInfo.TimeSeconds + 5.0;
		return false;
	}
	BBTurret = Best;
	BBTurretApproachStart = WorldInfo.TimeSeconds;
	SetGoalLocation(Best.Location);
	GotoState('GoThereAndStayThere');
	return true;
}

function BBLeaveTurret(string Why)
{
	local ROTurret T;

	T = ROTurret(Pawn);
	if (bBBTurretFiring && Pawn != none)
	{
		Pawn.StopFire(0);
	}
	bBBTurretFiring = false;
	bBBTurretUser = false;
	BBTurret = none;
	BBTurretNextUse = WorldInfo.TimeSeconds + 30.0;
	if (T != none)
	{
		`log("[BetterBots]"@BBName()@"leaves the fixed MG:"@Why);
		T.DriverLeave(true);
	}
	if (Vehicle(Pawn) == none)
	{
		GotoState('FindNextState');
	}
}

/** Relative yaw of a point from the gun's centre line is inside its traverse */
function bool BBTurretCanTraverse(ROTurret T, vector P)
{
	local int RelYaw;

	if (!T.bHasYawLimit)
	{
		return true;
	}
	RelYaw = NormalizeRotAxis(Rotator(P - T.Location).Yaw - T.Rotation.Yaw);
	return RelYaw >= T.YawLimit.X && RelYaw <= T.YawLimit.Y;
}

function bool BBTurretFriendlyInLine(vector Start, vector Target)
{
	local Pawn P;
	local vector Line;
	local float DistSq;

	Line = Normal(Target - Start);
	DistSq = VSizeSq(Target - Start);
	foreach WorldInfo.AllPawns(class'Pawn', P)
	{
		if (P != Pawn && P.Health > 0 && P.GetTeamNum() == GetTeamNum() && ((P.Location - Start) dot Line) > 0 &&
			VSizeSq(P.Location - Start) < DistSq && PointDistToLine(P.Location, Line, Start) < 120.0)
		{
			return true;
		}
	}
	return false;
}

function BBTurretTick()
{
	local ROTurret T;
	local Pawn P, Best;
	local PlayerController PC;
	local vector Eye, Aim;
	local float D, BestD;
	local ROObjective Obj;

	T = ROTurret(Pawn);
	if (T == none)
	{
		ClearTimer('BBTurretTick');
		return;
	}
	Eye = T.Location + vect(0,0,60);

	// A human walks up: give it to them
	foreach WorldInfo.AllControllers(class'PlayerController', PC)
	{
		if (PC.Pawn != none && PC.Pawn.Health > 0 && Vehicle(PC.Pawn) == none && PC.GetTeamNum() == GetTeamNum() &&
			VSize(PC.Pawn.Location - T.Location) < 300.0)
		{
			PC.ClientMessage("[BetterBots]"@BBName()@"te deja la ametralladora");
			BBLeaveTurret("human wants it");
			return;
		}
	}
	// The point is gone
	if (!BBDefendingObjective(Obj))
	{
		BBLeaveTurret("objective lost");
		return;
	}

	if (WorldInfo.TimeSeconds > BBTurretNextPick || BBTurretTarget == none || BBTurretTarget.Health <= 0)
	{
		BBTurretNextPick = WorldInfo.TimeSeconds + 1.0;
		BBTurretTarget = none;
		BestD = BB_TurretRange;
		foreach WorldInfo.AllPawns(class'Pawn', P)
		{
			if (P.Health <= 0 || P.GetTeamNum() == GetTeamNum() || P.GetTeamNum() > 1 || P.DrivenVehicle != none)
			{
				continue;
			}
			D = VSize(P.Location - T.Location);
			if (D > BB_TurretRange * ((ROVehicleHelicopter(P) != none) ? 1.4 : 1.0) || !FastTrace(P.Location + vect(0,0,40), Eye))
			{
				continue;
			}
			if (!BBTurretCanTraverse(T, P.Location))
			{
				// Close enemy the gun cannot turn to: we are flanked
				if (D < 2000.0 && ROVehicleHelicopter(P) == none)
				{
					BBLeaveTurret("flanked");
					return;
				}
				continue;
			}
			// Helicopters first, then the closest
			if (ROVehicleHelicopter(P) != none)
			{
				D *= 0.3;
			}
			if (D < BestD)
			{
				BestD = D;
				Best = P;
			}
		}
		BBTurretTarget = Best;
	}

	if (BBTurretTarget == none)
	{
		if (bBBTurretFiring)
		{
			Pawn.StopFire(0);
			bBBTurretFiring = false;
		}
		if (WorldInfo.TimeSeconds - BBTurretLastTarget > 60.0)
		{
			BBLeaveTurret("no targets for a minute");
		}
		return;
	}
	BBTurretLastTarget = WorldInfo.TimeSeconds;

	// Lead moving targets a little
	D = VSize(BBTurretTarget.Location - Eye);
	Aim = BBTurretTarget.Location + vect(0,0,35) + BBTurretTarget.Velocity * (D / 40000.0);
	Focus = BBTurretTarget;
	SetRotation(Rotator(Aim - Eye));

	if (!bBBTurretFiring && WorldInfo.TimeSeconds > BBTurretNextBurst && !BBTurretFriendlyInLine(Eye, Aim) &&
		(Normal(Aim - Eye) dot Vector(T.GetAdjustedAimFor(none, Eye))) > 0.995)
	{
		Pawn.StartFire(0);
		bBBTurretFiring = true;
		BBTurretBurstEnd = WorldInfo.TimeSeconds + 0.6 + FRand() * 0.8;
	}
	else if (bBBTurretFiring && WorldInfo.TimeSeconds > BBTurretBurstEnd)
	{
		Pawn.StopFire(0);
		bBBTurretFiring = false;
		BBTurretNextBurst = WorldInfo.TimeSeconds + 0.4 + FRand() * 0.6;
	}
}

function Possess(Pawn aPawn, bool bVehicleTransition)
{
	super.Possess(aPawn, bVehicleTransition);

	if (ROTurret(aPawn) != none && bBBTurretUser)
	{
		GotoState('BBTurreting');
	}
	else if (Vehicle(aPawn) == none)
	{
		bBBTurretUser = false;
		BBTurret = none;
	}
}

function BBTurretResume()
{
	if (bBBTurretUser && ROTurret(Pawn) != none && !IsInState('BBTurreting'))
	{
		GotoState('BBTurreting');
	}
}

state BBTurreting
{
	ignores SeePlayer, HearNoise, EnemyNotVisible, NotifyTakeHit, NotifyObjectivesUpdated;

	function EvaluateObjectives() {}

	event BeginState(Name PreviousStateName)
	{
		BBTurretLastTarget = WorldInfo.TimeSeconds;
		BBTurretManStart = WorldInfo.TimeSeconds;
		BBTurretTarget = none;
		bBBTurretFiring = false;
		SetTimer(0.2, true, 'BBTurretTick');
	}

	event EndState(Name NextStateName)
	{
		ClearTimer('BBTurretTick');
		if (bBBTurretFiring && Pawn != none)
		{
			Pawn.StopFire(0);
		}
		bBBTurretFiring = false;
		// Knocked out of the state by some stock event while still on the gun
		if (bBBTurretUser && ROTurret(Pawn) != none)
		{
			SetTimer(0.01, false, 'BBTurretResume');
		}
	}
}

defaultproperties
{
	BBCmdLastOwned=-1
}
