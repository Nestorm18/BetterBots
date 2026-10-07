//=============================================================================
// BBAIController
//=============================================================================
// Bot controller with fixes over the stock ROAIController:
//
// 1. Objective choice. The stock GetBestObjectiveIndex() ignores objective
//    priority and sends defenders to attack 80% of the time (and attackers
//    to defend 50% of the time), picking at random on every re-evaluation.
//    This version scores objectives: defenders guard their own points and
//    rush the ones being captured, attackers push enemy points and reinforce
//    captures in progress. Bots are spread across objectives and stick to
//    their choice instead of re-rolling every few seconds.
//
// 2. Midpoint bug. When the goal is more than ~80 m away the stock code
//    searches near (Pawn.Location - Goal) / 2, which is an offset vector,
//    not the midpoint, so bots get sent to a meaningless spot.
//
// 3. Stuck watchdog. A bot outside its objective that has not moved for a
//    while re-plans its route, and after repeated failures tries a
//    different objective for a while.
//
// 4. Personalities by role (UU: 50 per metre):
//    - Marksman: overwatch 50-90 m behind the objective, holds for minutes.
//    - Commander: command post 25-40 m behind, calls in abilities from there.
//    - Radioman: follows the commander (human or bot).
//    - Machine gunner: covers the enemy side of the objective edge.
//    - US squad leader: stays just behind the objective as a spawn point.
//    - Flankers (some riflemen/scouts/engineers): attack from the sides;
//      on defense they ambush from lateral positions instead of sitting
//      in the capture zone.
//
// 5. Fights draw bots in. An objective is "hot" while it is being captured
//    or has soldiers of both sides (or enemies in one of ours) inside. Bots
//    of both teams favour hot objectives, and flankers/MGs/squad leaders
//    with "joins fights" leave their posts to reinforce, then go back.
//
// 6. Combat behaviour (BBCombatTick, every 0.5 s):
//    - Suppression: heavily suppressed bots go prone, aim and react worse,
//      and timid ones fall back toward their side for a while.
//    - Morale: drops when nearby teammates die or objectives are lost, rises
//      with kills, captures and a living squad leader nearby. Low morale
//      makes attackers flank and keeps bots out of fights.
//    - Suppressive fire: MGs and some riflemen fire bursts at where an enemy
//      was last seen or heard, even without a visible target.
//    - Bounding: attacking squads in contact split into two fireteams (by
//      squad slot); one moves while the other holds and covers, alternating.
//    - Smoke: attackers in contact throw smoke toward the objective before
//      crossing open ground (clear line of sight to it).
//=============================================================================

class BBAIController extends ROAIController
	config(Game)
	dependson(ROSquadReplicationInfo);

enum EBBMode
{
	BBM_Assault,		// Stock behaviour: go into the objective
	BBM_Flanker,
	BBM_Overwatch,
	BBM_Command,
	BBM_Escort,
	BBM_SupportFire,
	BBM_Rally,
};

const BB_MaxNavDistSq		= 16000000.0;	// Same as the stock MaxNavDistanceSq (4000^2)
const BB_WatchdogInterval	= 4.0;			// Seconds between stuck checks
const BB_StuckDistSq		= 22500.0;		// Moving less than 150 UU between checks counts as not moving
const BB_StuckTicks			= 3;			// Checks without moving before we act (~12 s)
const BB_StuckStrikesMax	= 3;			// Re-plans before giving up on an objective
const BB_AvoidTime			= 30.0;			// Seconds to avoid an objective we could not reach

var		vector	BBLastWatchdogLocation;
var		int		BBStuckTicks;
var		int		BBStuckStrikes;
var		int		BBAvoidObjectiveIndex;
var		float	BBAvoidObjectiveUntil;
var		bool	bBBResponder;				// Defender that leaves its post to save a point under capture

var		EBBMode	BBMode;
var		bool	bBBHasPost;					// Holding a position outside the capture zone
var		vector	BBPostLocation;
var		int		BBPostObjective;			// Objective the post was chosen for
var		float	BBPostHoldTime;				// How long to stay once there
var		float	BBPostUntil;				// 0 until we arrive

var		bool	bBBJoinsFights;				// Leaves its post to reinforce a hot objective
var		bool	bBBReinforcing;
var		int		BBReinforceIndex;

var		bool	bBBFlankStaging;			// Heading to the wide flank staging point
var		bool	bBBFlankStaged;				// Reached it (or gave up), go in from the side
var		bool	bBBDefFlank;				// Flanker that ambushes from the side on defense
var		float	BBRoleRoll;					// 0-1 per life: counterattacker / rear guard

var		float	BBBravery;					// 0-1, fixed per bot
var		float	BBMorale;					// 0-1, changes during the match
var		int		BBLastOwnedObjectives;
var		float	BBPinnedUntil;
var		bool	bBBProneForCover;
var		float	BBFallBackUntil;
var		bool	bBBSuppressor;				// Lays down suppressive fire
var		float	BBLastSuppressTime;
var		vector	BBSuppressTarget;
var		float	BBSuppressEnd;
var		int		BBShots;
var		vector	BBHeardEnemyLocation;
var		float	BBHeardEnemyTime;
var		float	BBNextSmokeCheck;
var		float	BBLastSmokeThrow;
var		float	BBBoundHoldEnd;
var		float	BBNextBoundTime;

var		bool	bBBZoneMoving;				// Repositioning inside the capture zone
var		float	BBZoneNextMove;
var		float	BBNextZoneReeval;			// Next time a bot in a zone reconsiders its objective

// Helicopter pilot
var		bool				bBBHeliPilot;
var		ROVehicleHelicopter	BBHeli;
var		name				BBHeliMission;		// Hover, Goto, Home
var		name				BBHeliPhase;		// Spool, Climb, Transit, Loiter, Return, Approach, Descend, Landed, Done
var		float				BBHeliPhaseStart;
var		float				BBHeliFlightStart;
var		float				BBHeliHoverTime;	// Loiter time at the destination
var		float				BBHeliCollectiveTrim;	// Learned hover collective (0-1)
var		int					BBHeliTargetYaw;
var		vector				BBHeliHoldLocation;
var		vector				BBHeliDest;
var		vector				BBHeliHome;			// Take-off point, where it lands again
var		float				BBHeliTerrainZ;		// Cached cruise height over the ground ahead
var		float				BBHeliNextTerrain;
var		float				BBHeliObstacleUntil;
var		float				BBHeliNextLog;
var		float				BBHeliMaxAGL;
var		float				BBHeliTouchdownVZ;

event PostBeginPlay()
{
	super.PostBeginPlay();

	BBAvoidObjectiveIndex = -1;
	// Not every defender abandons its post when another point is attacked
	bBBResponder = FRand() < 0.4;
	BBBravery = FRand();
	BBMorale = BBMoraleBase();
	BBLastOwnedObjectives = -1;
	SetTimer(BB_WatchdogInterval + FRand(), true, 'BBWatchdog');
	SetTimer(0.5, true, 'BBCombatTick');
}

/*-----------------------------------------------------------------------------
	Personality
-----------------------------------------------------------------------------*/

function Possess(Pawn aPawn, bool bVehicleTransition)
{
	super.Possess(aPawn, bVehicleTransition);

	if (Vehicle(aPawn) == none)
	{
		BBChooseMode();
	}
	else if (bBBHeliPilot && ROVehicleHelicopter(aPawn) != none)
	{
		// The stock controller goes BrainDead in vehicles; fly instead
		BBHeli = ROVehicleHelicopter(aPawn);
		GotoState('BBHeliFly');
	}
}

/*-----------------------------------------------------------------------------
	Helicopter pilot
	Phase 0 (BBHeliTest): take off, hover, land.
	Phase 1 (BBHeliGoto): climb, fly to a point following the terrain,
	loiter, fly back to the take-off point and land.
-----------------------------------------------------------------------------*/

const BB_HeliHoverAGL		= 1500.0;	// 30 m
const BB_HeliLoiterAGL		= 2500.0;	// 50 m over a destination
const BB_HeliCruiseAGL		= 3000.0;	// 60 m over the highest ground ahead
const BB_HeliApproachAGL	= 1500.0;
const BB_HeliCruiseSpeed	= 1200.0;	// UU/s (~86 km/h), kept low while tuning
const BB_HeliMaxTilt		= 3641.0;	// 20 deg cyclic pitch/roll limit

function class<RORoleInfo> BBFindPilotRoleClass()
{
	local ROMapInfo ROMI;
	local array<RORoleCount> Roles;
	local int i;

	ROMI = ROMapInfo(WorldInfo.GetMapInfo());
	if (ROMI == none)
	{
		return none;
	}
	Roles = (GetTeamNum() == `AXIS_TEAM_INDEX) ? ROMI.NorthernRoles : ROMI.SouthernRoles;
	for (i = 0; i < Roles.Length; i++)
	{
		if (Roles[i].RoleInfoClass != none && Roles[i].RoleInfoClass.default.bIsPilot &&
			!Roles[i].RoleInfoClass.default.bIsTransportPilot)
		{
			return Roles[i].RoleInfoClass;
		}
	}
	return none;
}

/**
 * Makes this bot a pilot and puts it in the helicopter's pilot seat.
 * Mission: 'Hover' (phase 0 test) or 'Goto' (fly to Dest and back).
 */
function bool BBStartHeli(ROVehicleHelicopter Heli, name Mission, vector Dest, float LoiterSeconds)
{
	local ROPlayerReplicationInfo ROPRI;
	local class<RORoleInfo> PilotClass;

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || Pawn == none || Heli == none)
	{
		return false;
	}

	if (ROPRI.RoleInfo == none || !ROPRI.RoleInfo.bIsPilot)
	{
		PilotClass = BBFindPilotRoleClass();
		if (PilotClass == none)
		{
			`log("[BetterBots][Heli] No pilot role on this map for team"@GetTeamNum());
			return false;
		}
		LeaveSquad();
		if (!ROPRI.SelectRoleByClass(self, PilotClass))
		{
			`log("[BetterBots][Heli] Could not give pilot role"@PilotClass@"to"@ROPRI.PlayerName);
			return false;
		}
	}

	// Read by BBHeliFly.BeginState when DriverEnter possesses the helicopter
	bBBHeliPilot = true;
	BBHeliMission = Mission;
	BBHeliDest = Dest;
	BBHeliHoverTime = LoiterSeconds;
	if (!Heli.DriverEnter(Pawn))
	{
		`log("[BetterBots][Heli] DriverEnter refused for"@ROPRI.PlayerName@"in"@Heli);
		bBBHeliPilot = false;
		return false;
	}
	`log("[BetterBots][Heli]"@ROPRI.PlayerName@"is flying"@Heli@"mission"@Mission@"dest"@Dest@"loiter"@LoiterSeconds$"s");
	return true;
}

function bool BBStartHeliTest(ROVehicleHelicopter Heli, float HoverSeconds)
{
	return BBStartHeli(Heli, 'Hover', vect(0,0,0), HoverSeconds);
}

/** New orders for a bot that is already flying (or sitting landed in the pilot seat) */
function BBHeliRetask(name Mission, vector Dest, float LoiterSeconds)
{
	BBHeliMission = Mission;
	BBHeliDest = Dest;
	BBHeliHoverTime = LoiterSeconds;

	if (BBHeliPhase == 'Spool' || BBHeliPhase == 'Landed' || BBHeliPhase == 'Done')
	{
		BBHeliHoldLocation = BBHeli.Location;
		BBHeliSetPhase((BBHeliPhase == 'Spool') ? 'Spool' : 'Climb');
	}
	else if (Mission == 'Home')
	{
		BBHeliSetPhase('Return');
	}
	else
	{
		BBHeliSetPhase('Transit');
	}
	`log("[BetterBots][Heli] Retasked:"@Mission@"dest"@Dest);
}

function bool BBIsFlyingHeli()
{
	return bBBHeliPilot && BBHeli != none && BBHeli.Health > 0 && Pawn == BBHeli;
}

/** Height of the ground below a point (world geometry only) */
function float BBHeliGroundZ(vector P)
{
	local vector HitLocation, HitNormal, Start, End;

	Start = P;
	Start.Z = BBHeli.Location.Z + 8000.0;
	End = P;
	End.Z = BBHeli.Location.Z - 60000.0;
	if (Trace(HitLocation, HitNormal, End, Start, false) == none)
	{
		return End.Z;
	}
	return HitLocation.Z;
}

/** Height above ground under the helicopter, in UU */
function float BBHeliAGL()
{
	local vector HitLocation, HitNormal;

	if (Trace(HitLocation, HitNormal, BBHeli.Location - vect(0,0,60000), BBHeli.Location, false) == none)
	{
		return 60000.0;
	}
	return BBHeli.Location.Z - HitLocation.Z - BBHeli.AltitudeOffset;
}

/** Cruise altitude limited by the map ceiling */
function float BBHeliClampAGL(float WantedAGL)
{
	if (BBHeli.Ceiling > 0)
	{
		return FMin(WantedAGL, BBHeli.Ceiling - 300.0);
	}
	return WantedAGL;
}

/**
 * Absolute height to fly at: AGL over the highest ground on the path ahead
 * (samples up to ~3 s of flight ahead), refreshed 4 times a second.
 */
function float BBHeliTerrainTargetZ(vector Dir, float Speed, float DistToDest, float WantedAGL)
{
	local float Step, D, GroundZ, MaxGround;
	local int i;

	if (WorldInfo.TimeSeconds < BBHeliNextTerrain)
	{
		return BBHeliTerrainZ;
	}
	BBHeliNextTerrain = WorldInfo.TimeSeconds + 0.25;

	Step = FMax(Speed, 800.0);
	MaxGround = BBHeliGroundZ(BBHeli.Location);
	for (i = 1; i <= 3; i++)
	{
		D = FMin(Step * i, DistToDest + 500.0);
		GroundZ = BBHeliGroundZ(BBHeli.Location + Dir * D);
		MaxGround = FMax(MaxGround, GroundZ);
	}
	BBHeliTerrainZ = MaxGround + BBHeliClampAGL(WantedAGL) + BBHeli.AltitudeOffset;
	return BBHeliTerrainZ;
}

/** Something solid in the flight path within ~2.5 s (trees, buildings, hills) */
function bool BBHeliObstacleAhead(vector VelNoZ)
{
	local vector HitLocation, HitNormal, Ahead;

	if (VSize(VelNoZ) < 200.0)
	{
		return false;
	}
	Ahead = BBHeli.Location + VelNoZ * 2.5;
	Ahead.Z -= 200.0;
	return Trace(HitLocation, HitNormal, Ahead, BBHeli.Location, false) != none;
}

function BBHeliSetPhase(name NewPhase)
{
	`log("[BetterBots][Heli] Phase"@BBHeliPhase@"->"@NewPhase@"after"@int(WorldInfo.TimeSeconds - BBHeliPhaseStart)$"s");
	BBHeliPhase = NewPhase;
	BBHeliPhaseStart = WorldInfo.TimeSeconds;
}

/**
 * Autopilot. Collective holds a vertical speed (with a learned hover trim).
 * Cyclic tracks a desired horizontal velocity with the same pitch/roll law as
 * the stock auto-hover, limited to BB_HeliMaxTilt. Pedals hold a heading.
 */
function BBHeliControl(float DeltaTime)
{
	local vector X, Y, Z, VelNoZ, DesiredVel, VelErr, ToDest, Dir, Drift;
	local float AGL, VZ, DesiredVZ, TargetZ, Collective, SpeedNorm, TargetPitch, TargetRoll;
	local float InForward, InStrafe, InYaw, Dist, Speed, WantedSpeed;
	local bool bMoving, bObstacle;
	local int YawErr;

	if (!BBIsFlyingHeli())
	{
		`log("[BetterBots][Heli] Lost the helicopter (destroyed or left), phase"@BBHeliPhase);
		bBBHeliPilot = false;
		GotoState('FindNextState');
		return;
	}

	AGL = BBHeliAGL();
	VZ = BBHeli.Velocity.Z;
	VelNoZ = BBHeli.Velocity;
	VelNoZ.Z = 0;
	Speed = VSize(VelNoZ);
	BBHeliMaxAGL = FMax(BBHeliMaxAGL, AGL);

	// Destination for travelling phases
	if (BBHeliPhase == 'Return' || BBHeliPhase == 'Approach')
	{
		ToDest = BBHeliHome - BBHeli.Location;
	}
	else
	{
		ToDest = BBHeliDest - BBHeli.Location;
	}
	ToDest.Z = 0;
	Dist = VSize(ToDest);
	Dir = (Dist > 1.0) ? ToDest / Dist : vect(0,0,0);

	// --- Phase logic ---
	switch (BBHeliPhase)
	{
		case 'Spool':
			if (BBHeli.CurrentRPM >= BBHeli.NormalRPM * 0.95 || WorldInfo.TimeSeconds - BBHeliPhaseStart > 25.0)
			{
				BBHeliSetPhase('Climb');
			}
			break;
		case 'Climb':
			if (AGL > BB_HeliHoverAGL * 0.9)
			{
				BBHeliSetPhase((BBHeliMission == 'Hover') ? 'Loiter' : ((BBHeliMission == 'Home') ? 'Return' : 'Transit'));
			}
			else if (WorldInfo.TimeSeconds - BBHeliPhaseStart > 40.0)
			{
				`log("[BetterBots][Heli] Climb timed out at AGL"@int(AGL));
				BBHeliHoldLocation = BBHeli.Location;
				BBHeliSetPhase('Descend');
			}
			break;
		case 'Transit':
			if (Dist < 600.0 && Speed < 400.0)
			{
				BBHeliHoldLocation = BBHeliDest;
				BBHeliSetPhase('Loiter');
			}
			break;
		case 'Loiter':
			if (WorldInfo.TimeSeconds - BBHeliPhaseStart > BBHeliHoverTime)
			{
				if (BBHeliMission == 'Hover')
				{
					BBHeliHoldLocation = BBHeli.Location;
					BBHeliSetPhase('Descend');
				}
				else
				{
					BBHeliSetPhase('Return');
				}
			}
			break;
		case 'Return':
			if (Dist < 2500.0)
			{
				BBHeliSetPhase('Approach');
			}
			break;
		case 'Approach':
			if (Dist < 250.0 && Speed < 200.0)
			{
				BBHeliHoldLocation = BBHeliHome;
				BBHeliSetPhase('Descend');
			}
			break;
		case 'Descend':
			if (BBHeli.bVehicleOnGround || BBHeli.bWasChassisTouchingGroundLastTick)
			{
				BBHeliTouchdownVZ = VZ;
				BBHeliSetPhase('Landed');
			}
			break;
		case 'Landed':
			if (WorldInfo.TimeSeconds - BBHeliPhaseStart > 3.0)
			{
				`log("[BetterBots][Heli] FLIGHT DONE. Time"@int(WorldInfo.TimeSeconds - BBHeliFlightStart)$"s, max AGL"@int(BBHeliMaxAGL)@
					"UU, touchdown VZ ~"$int(BBHeliTouchdownVZ)@"UU/s, distance from home"@int(VSize(BBHeli.Location - BBHeliHome))@"UU, health"@BBHeli.Health);
				BBHeliSetPhase('Done');
			}
			break;
	}

	bMoving = (BBHeliPhase == 'Transit' || BBHeliPhase == 'Return' || BBHeliPhase == 'Approach');

	// --- Horizontal target ---
	if (bMoving)
	{
		WantedSpeed = FMin(BB_HeliCruiseSpeed, FMax(Dist * 0.35, 150.0));
		if (BBHeliPhase == 'Approach')
		{
			WantedSpeed = FMin(WantedSpeed, FMax(Dist * 0.3, 80.0));
		}
		TargetZ = BBHeliTerrainTargetZ(Dir, Speed, Dist, (BBHeliPhase == 'Approach') ? BB_HeliApproachAGL : BB_HeliCruiseAGL);

		bObstacle = BBHeliObstacleAhead(VelNoZ);
		if (bObstacle)
		{
			BBHeliObstacleUntil = WorldInfo.TimeSeconds + 3.0;
		}
		if (WorldInfo.TimeSeconds < BBHeliObstacleUntil)
		{
			// Something ahead: slow right down and climb over it
			WantedSpeed *= 0.3;
			TargetZ += 1500.0;
		}
		else if (TargetZ - BBHeli.Location.Z > 800.0)
		{
			// Rising ground ahead: slow down while climbing
			WantedSpeed *= 0.4;
		}
		DesiredVel = Dir * WantedSpeed;

		// Face where we are going
		if (Dist > 800.0)
		{
			BBHeliTargetYaw = Rotator(ToDest).Yaw;
		}
	}
	else
	{
		DesiredVel = (BBHeliHoldLocation - BBHeli.Location) * 0.5;
		DesiredVel.Z = 0;
		if (VSize(DesiredVel) > 300.0)
		{
			DesiredVel = Normal(DesiredVel) * 300.0;
		}
		if (BBHeliPhase == 'Loiter')
		{
			TargetZ = BBHeliGroundZ(BBHeli.Location) + BBHeli.AltitudeOffset +
				BBHeliClampAGL((BBHeliMission == 'Hover') ? BB_HeliHoverAGL : BB_HeliLoiterAGL);
		}
		else
		{
			TargetZ = BBHeliGroundZ(BBHeli.Location) + BBHeli.AltitudeOffset + BB_HeliHoverAGL;
		}
	}

	// --- Collective (vertical) ---
	if (BBHeliPhase == 'Spool' || BBHeliPhase == 'Landed' || BBHeliPhase == 'Done')
	{
		Collective = 0.0;
	}
	else
	{
		if (BBHeliPhase == 'Descend')
		{
			// Slow down well before the ground: the rotor loses RPM at high
			// collective, so braking late gives a hard touchdown
			if (AGL > 1000.0)
			{
				DesiredVZ = -250.0;
			}
			else if (AGL > 400.0)
			{
				DesiredVZ = -150.0;
			}
			else
			{
				DesiredVZ = -70.0;
			}
		}
		else
		{
			DesiredVZ = FClamp((TargetZ - BBHeli.Location.Z) * 0.8, -350.0, 500.0);
		}
		// Learn the hover point slowly (it changes with forward speed), then add a proportional term
		BBHeliCollectiveTrim = FClamp(BBHeliCollectiveTrim + 0.0005 * (DesiredVZ - VZ) * DeltaTime, 0.4, 0.98);
		Collective = FClamp(BBHeliCollectiveTrim + 0.0015 * (DesiredVZ - VZ), 0.0, 1.0);
	}

	// --- Cyclic and pedals, only once airborne ---
	if (BBHeliPhase != 'Spool' && BBHeliPhase != 'Landed' && BBHeliPhase != 'Done')
	{
		GetAxes(BBHeli.Rotation, X, Y, Z);
		X.Z = 0;
		Y.Z = 0;
		X = Normal(X);
		Y = Normal(Y);

		VelErr = VelNoZ - DesiredVel;
		SpeedNorm = FMax(BBHeli.MaxSpeed * 0.75, 1500.0);

		// Same law as ROVehicleHelicopter.HandleHoverInputs, with a tilt limit
		TargetPitch = FClamp(FClamp((VelErr dot X) / SpeedNorm, -1.0, 1.0) * BBHeli.MaxAutoHoverPitch, -BB_HeliMaxTilt, BB_HeliMaxTilt);
		TargetRoll = FClamp(FClamp((VelErr dot Y) / SpeedNorm, -1.0, 1.0) * BBHeli.MaxAutoHoverRoll, -BB_HeliMaxTilt, BB_HeliMaxTilt);
		InForward = FClamp((BBHeli.CurrentPitch - TargetPitch) / BBHeli.MaxAutoHoverPitch, -1.0, 1.0);
		InStrafe = FClamp((BBHeli.CurrentRoll - TargetRoll) / BBHeli.MaxAutoHoverRoll, -1.0, 1.0);

		YawErr = NormalizeRotAxis(BBHeliTargetYaw - BBHeli.Rotation.Yaw);
		InYaw = FClamp(YawErr / 8192.0, -0.5, 0.5);
	}

	// The stock auto-hover would overwrite our cyclic inputs
	if (BBHeli.bAutoHover)
	{
		BBHeli.ToggleAutoHover();
	}
	BBHeli.SetHeloInputs(InForward, InStrafe, 0, 0, Collective, InYaw);

	if (WorldInfo.TimeSeconds >= BBHeliNextLog)
	{
		BBHeliNextLog = WorldInfo.TimeSeconds + 1.0;
		Drift = BBHeli.Location - BBHeliHoldLocation;
		Drift.Z = 0;
		`log("[BetterBots][Heli]"@BBHeliPhase@"AGL="$int(AGL)@"VZ="$int(VZ)@"Spd="$int(Speed)@"Dist="$int(Dist)@
			"dZ="$int(TargetZ - BBHeli.Location.Z)@"RPM="$int(BBHeli.CurrentRPM)$"/"$int(BBHeli.NormalRPM)@
			"Coll="$Collective@"Trim="$BBHeliCollectiveTrim@"Pitch="$int(BBHeli.CurrentPitch * 0.0055)@"Roll="$int(BBHeli.CurrentRoll * 0.0055)@
			"YawErr="$int(YawErr * 0.0055)@"Hold="$int(VSize(Drift))@"Obst="$(WorldInfo.TimeSeconds < BBHeliObstacleUntil)@
			"In="$InForward$","$InStrafe$","$InYaw);
	}
}

state BBHeliFly
{
	ignores SeePlayer, HearNoise, EnemyNotVisible;

	function EvaluateObjectives() {}

	event BeginState(Name PreviousStateName)
	{
		BBHeliPhase = 'Spool';
		BBHeliPhaseStart = WorldInfo.TimeSeconds;
		BBHeliFlightStart = WorldInfo.TimeSeconds;
		BBHeliCollectiveTrim = 0.75;
		BBHeliTargetYaw = BBHeli.Rotation.Yaw;
		BBHeliHoldLocation = BBHeli.Location;
		BBHeliHome = BBHeli.Location;
		BBHeliMaxAGL = 0;
		BBHeliNextLog = 0;
		BBHeliNextTerrain = 0;
		BBHeliObstacleUntil = 0;
		`log("[BetterBots][Heli] Autopilot engaged at"@BBHeli.Location@"mission"@BBHeliMission);
	}

	event Tick(float DeltaTime)
	{
		global.Tick(DeltaTime);
		BBHeliControl(DeltaTime);
	}
}

function BBChooseMode()
{
	local ROPlayerReplicationInfo ROPRI;

	BBClearPost();
	BBMode = BBM_Assault;
	bBBReinforcing = false;
	bBBFlankStaging = false;
	bBBFlankStaged = false;
	// On defense most flankers stay in the zone; a couple go round the side
	bBBDefFlank = FRand() < 0.4;
	BBRoleRoll = FRand();

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || ROPRI.RoleInfo == none)
	{
		return;
	}

	if (ROPRI.RoleInfo.bIsTeamLeader)
	{
		BBMode = BBM_Command;
	}
	else if (ROPRI.bIsSquadLeader && GetTeamNum() == `ALLIES_TEAM_INDEX)
	{
		// US squad leaders are spawn points, keep them alive near the fight
		BBMode = BBM_Rally;
	}
	else
	{
		switch (ROPRI.RoleInfo.RoleType)
		{
			case RORIT_Marksman:
				BBMode = BBM_Overwatch;
				break;
			case RORIT_Radioman:
				BBMode = BBM_Escort;
				break;
			case RORIT_MachineGunner:
				BBMode = BBM_SupportFire;
				break;
			case RORIT_Scout:
				BBMode = (FRand() < 0.7) ? BBM_Flanker : BBM_Assault;
				break;
			case RORIT_Rifleman:
				BBMode = (FRand() < 0.4) ? BBM_Flanker : BBM_Assault;
				break;
			case RORIT_Engineer:
				BBMode = (FRand() < 0.3) ? BBM_Flanker : BBM_Assault;
				break;
			default:
				BBMode = BBM_Assault;
				break;
		}
	}

	bBBSuppressor = (BBMode == BBM_SupportFire) ||
		(ROPRI.RoleInfo.RoleType == RORIT_Rifleman && FRand() < 0.25);

	// Snipers, commanders and radiomen keep their distance
	switch (BBMode)
	{
		case BBM_Assault:		bBBJoinsFights = true; break;
		case BBM_Flanker:		bBBJoinsFights = FRand() < 0.5; break;
		case BBM_SupportFire:	bBBJoinsFights = FRand() < 0.35; break;
		case BBM_Rally:			bBBJoinsFights = FRand() < 0.3; break;
		default:				bBBJoinsFights = false; break;
	}
}

/*-----------------------------------------------------------------------------
	Hot objectives
-----------------------------------------------------------------------------*/

function BBCountInside(ROObjective Obj, out int NumFriendly, out int NumEnemy)
{
	local Pawn P;

	NumFriendly = 0;
	NumEnemy = 0;
	if (Obj.ObjVolume == none)
	{
		return;
	}

	foreach WorldInfo.AllPawns(class'Pawn', P)
	{
		if (P.Health > 0 && P.PlayerReplicationInfo != none && Obj.ObjVolume.EncompassesPoint(P.Location))
		{
			if (P.GetTeamNum() == GetTeamNum())
			{
				NumFriendly++;
			}
			else
			{
				NumEnemy++;
			}
		}
	}
}

/** 0 = quiet, 1+ = fighting going on */
function float BBHeat(ROObjective Obj)
{
	local int NumFriendly, NumEnemy;
	local float Heat;

	if (Obj == none || !Obj.bActive)
	{
		return 0;
	}

	BBCountInside(Obj, NumFriendly, NumEnemy);

	if (Obj.bCapping || Obj.CapProgress > 0.0)
	{
		Heat += 1.0 + Obj.CapProgress;
	}
	if (NumFriendly > 0 && NumEnemy > 0)
	{
		Heat += 1.0;
	}
	if (BBIsMine(Obj) && NumEnemy > 0)
	{
		Heat += 1.0;
	}
	return Heat;
}

/** Closest hot objective within reach, or -1 */
function int BBFindHotObjective()
{
	local ROGameInfoTerritories ROGIT;
	local int i, BestIndex;
	local float DistSq, BestDistSq;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none || Pawn == none)
	{
		return -1;
	}

	BestIndex = -1;
	BestDistSq = 64000000.0;	// 160 m
	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		if (ROGIT.Objectives[i] == none || !ROGIT.Objectives[i].bActive)
		{
			continue;
		}
		DistSq = VSizeSq(Pawn.Location - ROGIT.Objectives[i].Location);
		if (DistSq < BestDistSq && BBHeat(ROGIT.Objectives[i]) >= 1.0)
		{
			BestDistSq = DistSq;
			BestIndex = i;
		}
	}
	return BestIndex;
}

/** Leave the post to join a nearby fight. Returns true if we did. */
function bool BBMaybeJoinFight()
{
	local int HotIndex;

	// Flankers on their way round are already heading for the fight
	if (!bBBJoinsFights || bBBReinforcing || bBBFlankStaging || BBMorale < 0.35)
	{
		return false;
	}

	HotIndex = BBFindHotObjective();
	if (HotIndex < 0)
	{
		return false;
	}

	BBClearPost();
	bBBReinforcing = true;
	BBReinforceIndex = HotIndex;
	return true;
}

function BBClearPost()
{
	bBBHasPost = false;
	BBPostUntil = 0;
	BBPostObjective = -1;
}

function float BBRand(float A, float B)
{
	return A + FRand() * (B - A);
}

function float BBObjectiveRadius(ROObjective Obj)
{
	if (Obj.ObjVolume != none && Obj.ObjVolume.BrushComponent != none)
	{
		return FMax(Obj.ObjVolume.BrushComponent.Bounds.SphereRadius, 300.0);
	}
	return 1000.0;
}

/**
 * Point relative to the objective. Back > 0 is toward our own side (where we
 * spawned), Back < 0 toward the enemy. Side is lateral.
 */
function vector BBPointNearObjective(ROObjective Obj, float Back, float Side)
{
	local vector Fwd, Right, Target, Fallback;

	Fwd = Obj.Location - LastSpawnLocation;
	if (LastSpawnLocation == vect(0,0,0) || VSizeSq(Fwd) < 1.0)
	{
		Fwd = Obj.Location - Pawn.Location;
	}
	Fwd.Z = 0;
	Fwd = Normal(Fwd);
	Right.X = -Fwd.Y;
	Right.Y = Fwd.X;

	Target = Obj.Location - Fwd * Back + Right * Side;
	Fallback = NewGetObjectiveLocation();
	return GetValidLocationNear(Target, Fallback);
}

/** Picks a post for modes that do not go into the capture zone. Returns false to use the stock approach. */
function bool BBPickPost(ROObjective Obj)
{
	local float R, Side;
	local bool bDefender;

	R = BBObjectiveRadius(Obj);
	bDefender = BBIsDefender();
	Side = (FRand() < 0.5) ? -1.0 : 1.0;

	switch (BBMode)
	{
		case BBM_Overwatch:
			// Roams between distant firing positions, wide to either side; stays
			// as long as it has targets (see ShouldFindNewObjective)
			BBPostLocation = BBPointNearObjective(Obj, R + BBRand(3000, 6000), Side * BBRand(500, 4000));
			BBPostHoldTime = BBRand(35, 50);
			break;
		case BBM_Command:
		case BBM_Escort:	// Escort without a commander to follow
			BBPostLocation = BBPointNearObjective(Obj, R + BBRand(1200, 2000), BBRand(-800, 800));
			BBPostHoldTime = BBRand(40, 70);
			break;
		case BBM_SupportFire:
			if (bDefender)
			{
				// Edge of the zone facing the enemy
				BBPostLocation = BBPointNearObjective(Obj, -R * 0.6, BBRand(-R * 0.5, R * 0.5));
			}
			else
			{
				// Suppress from just behind the zone
				BBPostLocation = BBPointNearObjective(Obj, R + BBRand(500, 1200), BBRand(-R, R));
			}
			BBPostHoldTime = BBRand(40, 80);
			break;
		case BBM_Rally:
			BBPostLocation = BBPointNearObjective(Obj, R * 0.4 + BBRand(300, 900), BBRand(-R * 0.6, R * 0.6));
			BBPostHoldTime = BBRand(30, 60);
			break;
		case BBM_Flanker:
			if (!bDefender)
			{
				// Wide flank: first a staging point well off to one side, level with
				// the objective, then straight in from there (see FindNewObjective)
				if (bBBFlankStaged || VSize(Pawn.Location - Obj.Location) < R + 1500.0)
				{
					return false;
				}
				BBPostLocation = BBPointNearObjective(Obj, BBRand(0, R * 0.5), Side * (R + BBRand(2000, 4000)));
				BBPostHoldTime = BBRand(2, 5);
				bBBFlankStaging = true;
				break;
			}
			// Only some defenders leave the zone to ambush from the side
			if (!bBBDefFlank)
			{
				return false;
			}
			// Lateral ambush position, slightly toward the enemy
			BBPostLocation = BBPointNearObjective(Obj, -BBRand(R * 0.3, R), Side * BBRand(R * 1.3, R * 2.2));
			BBPostHoldTime = BBRand(25, 45);
			break;
		default:
			return false;
	}

	bBBHasPost = true;
	BBPostObjective = CurrentOrders.OrderIndex;
	BBPostUntil = 0;
	return true;
}

function bool BBIsHoldingPost()
{
	return bBBHasPost && BBPostUntil > 0 && Pawn != none && VSizeSq(Pawn.Location - BBPostLocation) < 160000.0; // 8 m
}

/** The team commander, human or bot */
function Controller BBFindCommander()
{
	local Controller C;
	local ROPlayerReplicationInfo ROPRI;

	foreach WorldInfo.AllControllers(class'Controller', C)
	{
		ROPRI = ROPlayerReplicationInfo(C.PlayerReplicationInfo);
		if (C != self && ROPRI != none && ROPRI.RoleInfo != none && ROPRI.RoleInfo.bIsTeamLeader &&
			C.GetTeamNum() == GetTeamNum() && C.Pawn != none && C.Pawn.Health > 0)
		{
			return C;
		}
	}
	return none;
}

/** Radiomen stay with the commander so abilities can be called in */
/**
 * Another radioman (bot following, or a human nearby) already with the commander.
 * bOnlyPriority: we are following too, so only escorts that outrank us (humans,
 * or bots that joined first by PlayerID) count - otherwise both would stay.
 */
function bool BBCommanderHasEscort(Controller Commander, bool bOnlyPriority)
{
	local Controller C;
	local ROPlayerReplicationInfo ROPRI;
	local ROAIController Bot;

	foreach WorldInfo.AllControllers(class'Controller', C)
	{
		ROPRI = ROPlayerReplicationInfo(C.PlayerReplicationInfo);
		if (C == self || C == Commander || ROPRI == none || ROPRI.RoleInfo == none ||
			ROPRI.RoleInfo.RoleType != RORIT_Radioman || C.GetTeamNum() != GetTeamNum() ||
			C.Pawn == none || C.Pawn.Health <= 0)
		{
			continue;
		}

		Bot = ROAIController(C);
		if (Bot != none)
		{
			if (Bot.CurrentOrders.OrderType == ROORDER_Follow && Bot.MyFollowActor == Commander.Pawn &&
				(!bOnlyPriority || Bot.PlayerReplicationInfo.PlayerID < PlayerReplicationInfo.PlayerID))
			{
				return true;
			}
		}
		else if (VSizeSq(C.Pawn.Location - Commander.Pawn.Location) < 1000000.0) // human within 20 m
		{
			return true;
		}
	}
	return false;
}

function BBUpdateEscort()
{
	local Controller Commander;

	Commander = BBFindCommander();

	// One radioman is enough; the rest go and fight
	if (Commander != none &&
		BBCommanderHasEscort(Commander, CurrentOrders.OrderType == ROORDER_Follow && MyFollowActor == Commander.Pawn))
	{
		if (CurrentOrders.OrderType == ROORDER_Follow)
		{
			ForceClearFollow();
		}
		BBMode = BBM_Assault;
		bBBJoinsFights = true;
		BBClearPost();
		return;
	}

	if (Commander != none)
	{
		if (CurrentOrders.OrderType != ROORDER_Follow || MyFollowActor != Commander.Pawn)
		{
			BBClearPost();
			ForceFollow(Commander);
		}
	}
	else if (CurrentOrders.OrderType == ROORDER_Follow)
	{
		ForceClearFollow();
	}
}

/**
 * Default engage (used from ScanHorizon/HoldObjective) can wander off after the
 * enemy. Bots in their capture zone or on a post fight from where they are.
 */
function ChooseEngageStyle(optional int ID)
{
	if (Enemy != none && EnemyIsValidShootTarget() && (InMyObjectiveArea(true) || BBIsHoldingPost()))
	{
		GoToState('EngageEnemyWithAnchor');
		return;
	}
	super.ChooseEngageStyle(ID);
}

function EvaluateObjectives()
{
	if (BBMode == BBM_Escort && Pawn != none && Pawn.Health > 0 && Vehicle(Pawn) == none)
	{
		BBUpdateEscort();
	}
	super.EvaluateObjectives();
}

/**
 * Replaces the stock version: same objective choice and approach, plus
 * role posts and flanking.
 */
function FindNewObjective()
{
	local ROObjective Obj;
	local int NewIndex;

	if (bBBReinforcing)
	{
		if (BBHeat(BBGetObjective(BBReinforceIndex)) >= 1.0)
		{
			BBClearPost();
			CurrentOrders.OrderIndex = BBReinforceIndex;
			CurrentOrders.OrderType = ROORDER_Resume;
			SetGoalLocation(NewGetObjectiveLocation());
			GotoState('GoThereAndStayThere');
			return;
		}
		bBBReinforcing = false;
	}

	NewIndex = GetBestObjectiveIndex();
	if (NewIndex < 0)
	{
		super.FindNewObjective();
		return;
	}

	if (bBBHasPost && NewIndex != BBPostObjective)
	{
		BBClearPost();
	}
	if (NewIndex != CurrentOrders.OrderIndex)
	{
		bBBFlankStaging = false;
		bBBFlankStaged = false;
	}
	CurrentOrders.OrderIndex = NewIndex;
	CurrentOrders.OrderType = ROORDER_Resume;
	Obj = BBGetObjective(NewIndex);

	// Reuse a post we have not finished holding (e.g. after a fight)
	if (bBBHasPost && (BBPostUntil == 0 || WorldInfo.TimeSeconds < BBPostUntil))
	{
		SetGoalLocation(BBPostLocation);
		GotoState('GoThereAndStayThere');
		return;
	}

	BBClearPost();
	if (Obj != none && Pawn != none && BBPickPost(Obj))
	{
		SetGoalLocation(BBPostLocation);
		GotoState('GoThereAndStayThere');
		return;
	}

	SetGoalLocation(NewGetObjectiveLocation());

	// Flankers that reached their staging point go straight in from the side.
	// Other attacking flankers (already close) and low-morale attackers use the
	// stock flank route; the rest use the stock 30% chance.
	if (bBBFlankStaged)
	{
		GotoState('GoThereAndStayThere');
	}
	else if ((BBMode == BBM_Flanker || BBMorale < 0.35) && !BBIsDefender())
	{
		FlankFinalGoal = GoalLocation;
		GotoState('FlankRoute');
	}
	else
	{
		ChooseObjectiveApproach();
	}
}

/*-----------------------------------------------------------------------------
	Objective helpers
-----------------------------------------------------------------------------*/

function ROObjective BBGetObjective(int Idx)
{
	local ROGameInfoTerritories ROGIT;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none || Idx < 0 || Idx >= ROGIT.Objectives.Length)
	{
		return none;
	}
	return ROGIT.Objectives[Idx];
}

function bool BBIsDefender()
{
	local ROGameInfoTerritories ROGIT;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	return ROGIT != none && ROGIT.DefendingTeam != DT_None && GetTeamNum() == ROGIT.DefendingTeam;
}

function bool BBIsMine(ROObjective Obj)
{
	return Obj.ObjState == EObjectiveState(GetTeamNum());
}

/** One of our objectives that the enemy is currently capturing */
function bool BBIsThreatened(ROObjective Obj)
{
	return BBIsMine(Obj) && Obj.CapTeamIndex == GetEnemyTeamIndex() && Obj.CapProgress > 0.0;
}

/** An objective our team is currently capturing */
function bool BBIsBeingCapturedByUs(ROObjective Obj)
{
	return !BBIsMine(Obj) && Obj.CapTeamIndex == GetTeamNum() && Obj.CapProgress > 0.0;
}

function byte BBGetPriority(ROObjective Obj)
{
	return (GetTeamNum() == `AXIS_TEAM_INDEX) ? Obj.GetAxisPriority() : Obj.GetAlliesPriority();
}

/** Counts active objectives that are ours and that are not ours */
function BBCountActive(out int NumMine, out int NumOther, out int NumThreatened)
{
	local ROGameInfoTerritories ROGIT;
	local int i;

	NumMine = 0;
	NumOther = 0;
	NumThreatened = 0;
	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none)
	{
		return;
	}

	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		if (ROGIT.Objectives[i] == none || !ROGIT.Objectives[i].bActive)
		{
			continue;
		}
		if (BBIsMine(ROGIT.Objectives[i]))
		{
			NumMine++;
			if (BBIsThreatened(ROGIT.Objectives[i]))
			{
				NumThreatened++;
			}
		}
		else
		{
			NumOther++;
		}
	}
}

/** Is the objective we are heading to still worth going to? */
function bool BBIsCurrentObjectiveUseful()
{
	local ROObjective Obj;
	local int NumMine, NumOther, NumThreatened;

	Obj = BBGetObjective(CurrentOrders.OrderIndex);
	if (Obj == none || !Obj.bActive)
	{
		return false;
	}

	BBCountActive(NumMine, NumOther, NumThreatened);

	if (BBIsDefender())
	{
		// A responder guarding a quiet point should go help a point under capture
		if (bBBResponder && NumThreatened > 0 && !BBIsThreatened(Obj))
		{
			return false;
		}
		// Guard our own points; counterattackers also go for lost ones
		return BBIsMine(Obj) || NumMine == 0 || BBIsCounterAttacker();
	}

	// Attackers: keep pushing enemy points; our own only if it is being taken
	// back, there is nothing else to attack, or we are its rear guard
	return !BBIsMine(Obj) || BBIsThreatened(Obj) || NumOther == 0 || BBIsRearGuard();
}

/** About a third of defenders try to retake lost points that are still active */
function bool BBIsCounterAttacker()
{
	return BBRoleRoll < 0.35 && BBMode != BBM_Command && BBMode != BBM_Escort && BBMode != BBM_Overwatch;
}

/** About one in five attackers stays to hold a point just taken */
function bool BBIsRearGuard()
{
	return BBRoleRoll < 0.2 && (BBMode == BBM_Assault || BBMode == BBM_SupportFire);
}

/*-----------------------------------------------------------------------------
	Objective selection
-----------------------------------------------------------------------------*/

/**
 * Replaces the stock random choice. Returns an index into ROGIT.Objectives,
 * which is how every caller uses CurrentOrders.OrderIndex.
 */
function int GetBestObjectiveIndex()
{
	local ROGameInfoTerritories ROGIT;
	local ROAIController Bot;
	local ROObjective Obj;
	local array<int> Assigned;
	local int i, BestIndex, NumMine, NumOther, NumThreatened;
	local float Score, BestScore;
	local bool bDefender;

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none || Pawn == none || ROGIT.Objectives.Length == 0)
	{
		return super.GetBestObjectiveIndex();
	}

	bDefender = BBIsDefender();
	BBCountActive(NumMine, NumOther, NumThreatened);

	// How many teammate bots are already going to each objective
	Assigned.Length = ROGIT.Objectives.Length;
	foreach WorldInfo.AllControllers(class'ROAIController', Bot)
	{
		if (Bot != self && Bot.Pawn != none && Bot.GetTeamNum() == GetTeamNum() &&
			Bot.CurrentOrders.OrderIndex >= 0 && Bot.CurrentOrders.OrderIndex < Assigned.Length)
		{
			Assigned[Bot.CurrentOrders.OrderIndex]++;
		}
	}

	BestIndex = -1;
	BestScore = -1000000.0;

	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		Obj = ROGIT.Objectives[i];
		if (Obj == none || !Obj.bActive)
		{
			continue;
		}

		if (bDefender)
		{
			if (BBIsThreatened(Obj))
			{
				// Responders rush the point closest to falling; others still lean toward it
				Score = (bBBResponder ? 700.0 : 300.0) + Obj.CapProgress * 600.0;
			}
			else if (BBIsMine(Obj))
			{
				Score = 500.0;
			}
			else if (NumMine == 0)
			{
				// Nothing left to defend: everyone counterattacks
				Score = 500.0;
			}
			else
			{
				// A lost point that is still capturable: some defenders try to
				// retake it so the front moves back and forth
				Score = BBIsCounterAttacker() ? 700.0 : 150.0;
			}
		}
		else
		{
			if (!BBIsMine(Obj))
			{
				Score = 500.0;
				if (BBIsBeingCapturedByUs(Obj))
				{
					// Reinforce a capture in progress
					Score += 200.0 + Obj.CapProgress * 200.0;
				}
			}
			else if (BBIsThreatened(Obj) && Obj.CapProgress > 0.5)
			{
				Score = 450.0;
			}
			else if (NumOther == 0)
			{
				Score = 300.0;
			}
			else
			{
				// A point we just took: a few stay behind to hold it
				Score = BBIsRearGuard() ? 520.0 : -500.0;
			}
		}

		// Fights draw bots in from both teams
		Score += (bBBJoinsFights ? 300.0 : 100.0) * FMin(BBHeat(Obj), 2.0);

		// Lower priority value = earlier objective in the map's sequence
		Score -= 40.0 * Min(BBGetPriority(Obj), 10);

		// Prefer closer objectives (capped so distance never dominates the role)
		Score -= FMin(VSize(Pawn.Location - Obj.Location) / 50.0, 250.0);

		// Spread the team across objectives
		Score -= 25.0 * Assigned[i];

		// Stick to the current choice instead of re-rolling every evaluation
		if (i == CurrentOrders.OrderIndex)
		{
			Score += 150.0;
		}

		// Temporarily avoid an objective we kept getting stuck on
		if (i == BBAvoidObjectiveIndex && WorldInfo.TimeSeconds < BBAvoidObjectiveUntil)
		{
			Score -= 400.0;
		}

		Score += FRand() * 50.0;

		if (Score > BestScore)
		{
			BestScore = Score;
			BestIndex = i;
		}
	}

	if (BestIndex < 0)
	{
		return super.GetBestObjectiveIndex();
	}
	return BestIndex;
}

/**
 * The stock hold state mostly crouches in one spot staring at the horizon.
 * Move around the zone instead: often when the capture is stuck (attackers)
 * or enemies are inside (defenders) to hunt them out, now and then otherwise.
 */
function bool BBShouldMoveInZone()
{
	local ROObjective Obj;
	local int NumFriendly, NumEnemy;
	local bool bHunt;

	if (WorldInfo.TimeSeconds < BBZoneNextMove || (Enemy != none && CanSee(Enemy)))
	{
		return false;
	}
	Obj = BBGetObjective(CurrentOrders.OrderIndex);
	if (Obj == none)
	{
		return false;
	}

	if (BBIsDefender())
	{
		BBCountInside(Obj, NumFriendly, NumEnemy);
		bHunt = NumEnemy > 0;
	}
	else
	{
		// Not ours and we are not capturing it: someone is hiding in there
		bHunt = !BBIsMine(Obj) && !(Obj.bCapping && Obj.CapTeamIndex == GetTeamNum());
	}

	if (bHunt)
	{
		BBZoneNextMove = WorldInfo.TimeSeconds + BBRand(6, 10);
		return true;
	}

	// Quiet: reposition every so often instead of standing still forever
	BBZoneNextMove = WorldInfo.TimeSeconds + BBRand(15, 30);
	return FRand() < 0.5;
}

/**
 * The stock version re-picks an objective (and a new random goal point) every
 * evaluation unless the bot is in GoThereAndStayThere. Only re-pick when the
 * current objective is no longer worth it.
 */
function bool ShouldFindNewObjective(bool CurrentlyInHoldObjective)
{
	// Fell back under fire: stay low for a while before going again
	if (WorldInfo.TimeSeconds < BBFallBackUntil)
	{
		if (!IsInState('GoThereAndStayThere', true) && !IsInState('ScanHorizon'))
		{
			GoToState('ScanHorizon');
		}
		return false;
	}

	if (bBBHasPost)
	{
		if (!BBIsCurrentObjectiveUseful() || BBMaybeJoinFight())
		{
			BBClearPost();
			return true;
		}

		if (Pawn != none && VSizeSq(Pawn.Location - BBPostLocation) < 160000.0) // 8 m
		{
			if (BBPostUntil == 0)
			{
				BBPostUntil = WorldInfo.TimeSeconds + BBPostHoldTime;
				if (BBMode == BBM_Overwatch && Pawn != none && !Pawn.bIsProning)
				{
					// Snipers go to ground to stay hidden
					Pawn.ShouldProne(true);
				}
			}

			// A sniper with targets keeps its hide; one that sees nothing moves on
			if (BBMode == BBM_Overwatch && LastSightTime > 0 && WorldInfo.TimeSeconds - LastSightTime < 25.0)
			{
				BBPostUntil = FMax(BBPostUntil, WorldInfo.TimeSeconds + 20.0);
			}

			if (WorldInfo.TimeSeconds < BBPostUntil)
			{
				// Commanders call in support from their post
				if (BBMode == BBM_Command && ShouldCallInAbility())
				{
					GoToState('CallInAbility');
				}
				else if (!IsInState('ScanHorizon'))
				{
					GoToState('ScanHorizon');
				}
				return false;
			}

			// Done here, move to a new position (or in from the flank)
			if (bBBFlankStaging)
			{
				bBBFlankStaging = false;
				bBBFlankStaged = true;
			}
			BBClearPost();
			return true;
		}

		// Still travelling to the post
		return !IsInState('GoThereAndStayThere', true);
	}

	if (bBBReinforcing && BBHeat(BBGetObjective(BBReinforceIndex)) < 1.0)
	{
		// Fight's over, back to our usual role
		bBBReinforcing = false;
		return true;
	}

	if (InMyObjectiveArea(true) && BBIsCurrentObjectiveUseful())
	{
		// Let a move inside the zone finish
		if (bBBZoneMoving && IsInState('GoThereAndStayThere', true))
		{
			return false;
		}
		bBBZoneMoving = false;

		// Every so often reconsider: the fight may have moved (e.g. a lost point
		// is now worth retaking). The stickiness bonus in GetBestObjectiveIndex
		// keeps bots from flip-flopping between zones.
		if (WorldInfo.TimeSeconds >= BBNextZoneReeval)
		{
			BBNextZoneReeval = WorldInfo.TimeSeconds + BBRand(10, 15);
			if (GetBestObjectiveIndex() != CurrentOrders.OrderIndex)
			{
				return true;
			}
		}

		if (BBShouldMoveInZone())
		{
			bBBZoneMoving = true;
			SetGoalLocation(NewGetObjectiveLocation());	// Random point inside the zone
			GotoState('GoThereAndStayThere');
			return false;
		}

		if (!CurrentlyInHoldObjective)
		{
			GoToState('HoldObjective');
		}
		return false;
	}

	if (IsInState('GoThereAndStayThere', true))
	{
		return !BBIsCurrentObjectiveUseful();
	}

	return true;
}

/**
 * Same as the stock version, with the midpoint fixed and a fallback for
 * objective volumes that have no cached pawn locations.
 */
function vector NewGetObjectiveLocation()
{
	local ROObjective Obj;
	local vector NewLoc;

	Obj = BBGetObjective(CurrentOrders.OrderIndex);
	if (Pawn == none || Obj == none)
	{
		return super.NewGetObjectiveLocation();
	}

	if (Obj.ObjVolume != none && Obj.ObjVolume.ValidLocationsForPawns.Length > 0)
	{
		NewLoc = Obj.ObjVolume.ValidLocationsForPawns[Rand(Obj.ObjVolume.ValidLocationsForPawns.Length)];
	}
	else
	{
		NewLoc = GetValidLocationNear(Obj.Location, Obj.Location);
	}

	if (VSizeSq(Pawn.Location - NewLoc) > BB_MaxNavDistSq)
	{
		// Stock code used (Pawn.Location - NewLoc) / 2 here, which is not the midpoint
		return GetValidLocationNear((Pawn.Location + NewLoc) * 0.5, NewLoc);
	}
	return NewLoc;
}

/*-----------------------------------------------------------------------------
	Morale
-----------------------------------------------------------------------------*/

function float BBMoraleBase()
{
	return 0.45 + 0.35 * BBBravery;
}

function BBAddMorale(float Delta)
{
	BBMorale = FClamp(BBMorale + Delta, 0.0, 1.0);
}

function bool BBSquadLeaderNear()
{
	local ROPlayerReplicationInfo ROPRI;
	local Controller SL;

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || ROPRI.Squad == none || Pawn == none)
	{
		return false;
	}
	SL = ROPRI.Squad.GetSquadLeader();
	return SL != none && SL != self && SL.Pawn != none && SL.Pawn.Health > 0 &&
		VSizeSq(SL.Pawn.Location - Pawn.Location) < 6250000.0; // 50 m
}

/** Morale drifts back toward the bot's base, higher with its squad leader nearby */
function BBUpdateMorale(float DeltaTime)
{
	local float Target;

	Target = BBMoraleBase();
	if (BBSquadLeaderNear())
	{
		Target += 0.1;
	}
	BBMorale += (Target - BBMorale) * FMin(DeltaTime * 0.03, 1.0);
	BBMorale = FClamp(BBMorale, 0.0, 1.0);
}

function NotifyKilled(Controller Killer, Controller Killed, Pawn KilledPawn, class<DamageType> damageType)
{
	super.NotifyKilled(Killer, Killed, KilledPawn, damageType);
	BBOnKilled(Killer, Killed, KilledPawn);
}

function BBOnKilled(Controller Killer, Controller Killed, Pawn KilledPawn)
{
	local ROPlayerReplicationInfo MyPRI, KilledPRI;
	local int KilledTeam;
	local bool bNear;

	if (Pawn == none || KilledPawn == none || Killed == self)
	{
		return;
	}

	KilledTeam = (Killed != none) ? Killed.GetTeamNum() : KilledPawn.GetTeamNum();
	bNear = VSizeSq(KilledPawn.Location - Pawn.Location) < 4000000.0; // 40 m

	if (KilledTeam == GetTeamNum())
	{
		if (bNear)
		{
			BBAddMorale(-0.07);

			MyPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
			if (Killed != none)
			{
				KilledPRI = ROPlayerReplicationInfo(Killed.PlayerReplicationInfo);
			}
			if (MyPRI != none && KilledPRI != none && MyPRI.Squad != none && MyPRI.Squad == KilledPRI.Squad)
			{
				BBAddMorale(KilledPRI.bIsSquadLeader ? -0.12 : -0.05);
			}
		}
	}
	else if (Killer == self)
	{
		BBAddMorale(0.06);
	}
	else if (bNear)
	{
		BBAddMorale(0.03);
	}
}

function NotifyObjectivesUpdated()
{
	local ROGameInfoTerritories ROGIT;
	local int i, Owned;

	super.NotifyObjectivesUpdated();

	ROGIT = ROGameInfoTerritories(WorldInfo.Game);
	if (ROGIT == none)
	{
		return;
	}
	for (i = 0; i < ROGIT.Objectives.Length; i++)
	{
		if (ROGIT.Objectives[i] != none && BBIsMine(ROGIT.Objectives[i]))
		{
			Owned++;
		}
	}

	if (BBLastOwnedObjectives >= 0)
	{
		if (Owned > BBLastOwnedObjectives)
		{
			BBAddMorale(0.15);
		}
		else if (Owned < BBLastOwnedObjectives)
		{
			BBAddMorale(-0.15);
		}
	}
	BBLastOwnedObjectives = Owned;
}

/*-----------------------------------------------------------------------------
	Suppression effects
-----------------------------------------------------------------------------*/

/** Higher = worse aim. Suppression and low morale make bots miss more. */
function float GetAccuracyScale()
{
	return super.GetAccuracyScale() * (1.0 + 1.5 * GetSuppression() / 100.0) * (1.15 - 0.3 * BBMorale);
}

/** Higher = slower reactions */
function float GetReactionTimeScale()
{
	return super.GetReactionTimeScale() * (1.0 + 0.8 * GetSuppression() / 100.0);
}

function float BBCourage()
{
	return (BBBravery + BBMorale) * 0.5;
}

function BBUpdateSuppressionReaction()
{
	local float Suppressed, Courage;

	Suppressed = GetSuppression();
	Courage = BBCourage();

	// Brave bots tolerate more before hitting the dirt
	if (Suppressed > 55.0 + 30.0 * Courage)
	{
		if (WorldInfo.TimeSeconds > BBPinnedUntil)
		{
			BBPinnedUntil = WorldInfo.TimeSeconds + BBRand(2.0, 4.0) + (1.0 - Courage) * 3.0;
			BBAddMorale(-0.02);

			// Timid bots crawl back toward their side
			if (Suppressed > 80.0 && Courage < 0.4 && FRand() < 0.5 && !bCantOverrideState &&
				!InMyObjectiveArea(true) && !BBIsHoldingPost())
			{
				BBFallBack();
			}
		}

		if (!Pawn.bIsProning)
		{
			Pawn.ShouldProne(true);
			bBBProneForCover = true;
		}
	}
	else if (bBBProneForCover && WorldInfo.TimeSeconds > BBPinnedUntil && Suppressed < 35.0)
	{
		bBBProneForCover = false;
		// Snipers on their post stay down
		if (!(BBMode == BBM_Overwatch && BBIsHoldingPost()))
		{
			Pawn.ShouldProne(false);
		}
	}
}

function BBFallBack()
{
	local vector Dir, Target;

	if (LastSpawnLocation == vect(0,0,0))
	{
		return;
	}
	Dir = LastSpawnLocation - Pawn.Location;
	Dir.Z = 0;
	Dir = Normal(Dir);
	Target = GetValidLocationNear(Pawn.Location + Dir * BBRand(600, 1200), Pawn.Location);

	BBClearPost();
	bBBReinforcing = false;
	BBFallBackUntil = WorldInfo.TimeSeconds + BBRand(10, 16);
	SetGoalLocation(Target);
	GotoState('GoThereAndStayThere');
}

/*-----------------------------------------------------------------------------
	Suppressive fire
-----------------------------------------------------------------------------*/

event HearNoise(float Loudness, Actor NoiseMaker, optional Name NoiseType)
{
	local Pawn P;

	P = Pawn(NoiseMaker);
	if (P == none && NoiseMaker != none)
	{
		P = NoiseMaker.Instigator;
	}
	if (P != none && Pawn != none && P.Health > 0 && P.GetTeamNum() < 2 && P.GetTeamNum() != GetTeamNum())
	{
		// Only a rough idea of where it came from
		BBHeardEnemyLocation = P.Location;
		BBHeardEnemyLocation.X += BBRand(-250, 250);
		BBHeardEnemyLocation.Y += BBRand(-250, 250);
		BBHeardEnemyTime = WorldInfo.TimeSeconds;
	}

	super.HearNoise(Loudness, NoiseMaker, NoiseType);
}

function bool BBHasAmmo()
{
	local ROWeapon W;

	if (Pawn != none)
	{
		W = ROWeapon(Pawn.Weapon);
	}
	return W != none && W.GetAmmoCount() > 0;
}

function bool BBGetSuppressTarget(out vector Target)
{
	local float DistSq;

	if (LastSightLocation != vect(0,0,0) && LastSightTime > 0 && WorldInfo.TimeSeconds - LastSightTime < 10.0)
	{
		Target = LastSightLocation;
	}
	else if (BBHeardEnemyTime > 0 && WorldInfo.TimeSeconds - BBHeardEnemyTime < 6.0)
	{
		Target = BBHeardEnemyLocation;
	}
	else
	{
		return false;
	}

	DistSq = VSizeSq(Target - Pawn.Location);
	return DistSq > 360000.0 && DistSq < 49000000.0; // 12-140 m
}

/** The stock check needs a visible enemy, so do our own for a location */
function bool BBFriendlyInFireLine(vector Target)
{
	local Controller C;
	local vector Start, Line;
	local float TargetDistSq;

	Start = Pawn.Location;
	Line = Normal(Target - Start);
	TargetDistSq = VSizeSq(Target - Start);

	foreach WorldInfo.AllControllers(class'Controller', C)
	{
		if (C != self && C.Pawn != none && C.Pawn.Health > 0 && C.GetTeamNum() == GetTeamNum() &&
			((C.Pawn.Location - Start) dot Line) > 0 &&
			VSizeSq(C.Pawn.Location - Start) < TargetDistSq &&
			PointDistToLine(C.Pawn.Location, Line, Start) < 120.0)
		{
			return true;
		}
	}
	return false;
}

function bool BBTrySuppressiveFire()
{
	local vector Target;

	if (!bBBSuppressor || WorldInfo.TimeSeconds - BBLastSuppressTime < 8.0)
	{
		return false;
	}
	// Visible enemies are handled by the normal engage code
	if (Enemy != none && CanSee(Enemy))
	{
		return false;
	}
	// Only from a stable position
	if (!(BBIsHoldingPost() || InMyObjectiveArea(true) || IsInState('ScanHorizon') || IsInState('BBBoundHold')))
	{
		return false;
	}
	if (!BBHasAmmo() || !BBGetSuppressTarget(Target))
	{
		return false;
	}

	BBSuppressTarget = Target;
	BBLastSuppressTime = WorldInfo.TimeSeconds;
	GotoState('BBSuppressing');
	return true;
}

function float BBFireInterval()
{
	if (Pawn != none && Pawn.Weapon != none && Pawn.Weapon.FireInterval.Length > 0)
	{
		return FMax(Pawn.Weapon.FireInterval[0], 0.05);
	}
	return 0.2;
}

function vector BBSuppressAimPoint()
{
	local vector P;

	P = BBSuppressTarget;
	P.X += BBRand(-200, 200);
	P.Y += BBRand(-200, 200);
	P.Z += 40.0;
	return P;
}

state BBSuppressing
{
	function EvaluateObjectives() {}

	event BeginState(Name PreviousStateName)
	{
		super.BeginState(PreviousStateName);
		bCantOverrideState = true;
		BBSuppressEnd = WorldInfo.TimeSeconds + BBRand(4.0, 8.0);
		if (Pawn != none)
		{
			Pawn.ZeroMovementVariables();
			if (!Pawn.bIsProning)
			{
				Pawn.ShouldCrouch(true);
			}
		}
	}

	event EndState(Name NextStateName)
	{
		super.EndState(NextStateName);
		bCantOverrideState = false;
		if (Pawn != none)
		{
			Pawn.StopFiring();
			Pawn.ShouldCrouch(false);
		}
	}

Begin:
	Focus = none;
	SetFocalPoint(BBSuppressTarget + vect(0,0,40));
	Sleep(0.6 + FRand() * 0.4);

Burst:
	if (Pawn == none || WorldInfo.TimeSeconds > BBSuppressEnd || !BBHasAmmo() || (Enemy != none && CanSee(Enemy)))
	{
		Goto('Done');
	}
	SetFocalPoint(BBSuppressAimPoint());
	Sleep(0.15);
	if (BBFriendlyInFireLine(BBSuppressTarget))
	{
		Goto('Pause');
	}
	BBShots = (BBMode == BBM_SupportFire) ? 4 + Rand(6) : 1 + Rand(2);

Shoot:
	Pawn.BotFire(true);
	Sleep(BBFireInterval());
	BBShots--;
	if (BBShots > 0 && BBHasAmmo())
	{
		Goto('Shoot');
	}
	Pawn.StopFiring();

Pause:
	Sleep(BBRand(0.5, 1.5));
	Goto('Burst');

Done:
	if (Pawn != none)
	{
		Pawn.StopFiring();
	}
	GotoState('FindNextState');
}

/*-----------------------------------------------------------------------------
	Bounding (one fireteam moves, the other covers)
-----------------------------------------------------------------------------*/

function bool BBSquadInContact()
{
	local ROPlayerReplicationInfo ROPRI;
	local ROAIController Mate;
	local int i;

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || ROPRI.Squad == none)
	{
		return false;
	}
	for (i = 0; i < `MAX_ROLES_PER_SQUAD; i++)
	{
		Mate = ROAIController(ROPRI.Squad.GetOwner(i));
		if (Mate != none && Mate.Pawn != none && Mate.Pawn.Health > 0 &&
			((Mate.LastSightTime > 0 && WorldInfo.TimeSeconds - Mate.LastSightTime < 12.0) || Mate.GetSuppression() > 20.0))
		{
			return true;
		}
	}
	return false;
}

function bool BBShouldHoldForBound()
{
	local ROPlayerReplicationInfo ROPRI;
	local ROObjective Obj;
	local float Dist;
	local int Phase;

	if (BBIsDefender() || (BBMode != BBM_Assault && BBMode != BBM_Flanker) || bBBReinforcing || bBBHasPost)
	{
		return false;
	}
	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || ROPRI.Squad == none || ROPRI.RoleIndex == `ROLE_INDEX_NONE)
	{
		return false;
	}
	Obj = BBGetObjective(CurrentOrders.OrderIndex);
	if (Obj == none || Pawn == none)
	{
		return false;
	}
	// Only in the approach, not far away and not once inside
	Dist = VSize(Pawn.Location - Obj.Location);
	if (Dist < BBObjectiveRadius(Obj) * 1.1 || Dist > 7000.0)
	{
		return false;
	}
	if (!BBSquadInContact())
	{
		return false;
	}

	// Squad-wide clock: fireteams (odd/even slots) swap every 7 s
	Phase = int((WorldInfo.TimeSeconds + ROPRI.SquadIndex * 2.7) / 7.0) % 2;
	return Phase != (ROPRI.RoleIndex % 2);
}

function BBTryBound()
{
	if (WorldInfo.TimeSeconds < BBNextBoundTime || Enemy != none || !IsInState('GoThereAndStayThere'))
	{
		return;
	}
	if (BBShouldHoldForBound())
	{
		GotoState('BBBoundHold');
	}
}

function BBFaceObjective()
{
	local ROObjective Obj;

	Obj = BBGetObjective(CurrentOrders.OrderIndex);
	if (Obj != none)
	{
		Focus = none;
		SetFocalPoint(Obj.Location + vect(0,0,60));
	}
}

state BBBoundHold
{
	function EvaluateObjectives() {}

	event BeginState(Name PreviousStateName)
	{
		super.BeginState(PreviousStateName);
		bCantOverrideState = true;
		BBBoundHoldEnd = WorldInfo.TimeSeconds + 10.0;
		if (Pawn != none)
		{
			Pawn.ZeroMovementVariables();
			if (!Pawn.bIsProning)
			{
				Pawn.ShouldCrouch(true);
			}
		}
	}

	event EndState(Name NextStateName)
	{
		super.EndState(NextStateName);
		bCantOverrideState = false;
		BBNextBoundTime = WorldInfo.TimeSeconds + 4.0;
		if (Pawn != none && NextStateName != 'BBSuppressing')
		{
			Pawn.ShouldCrouch(false);
		}
	}

Begin:
	BBFaceObjective();
Wait:
	Sleep(0.5);
	if (WorldInfo.TimeSeconds > BBBoundHoldEnd || !BBShouldHoldForBound())
	{
		GotoState('FindNextState');
	}
	Goto('Wait');
}

/*-----------------------------------------------------------------------------
	Smoke before crossing open ground
-----------------------------------------------------------------------------*/

function bool BBSquadSmokedRecently()
{
	local ROPlayerReplicationInfo ROPRI;
	local BBAIController Mate;
	local int i;

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || ROPRI.Squad == none)
	{
		return false;
	}
	for (i = 0; i < `MAX_ROLES_PER_SQUAD; i++)
	{
		Mate = BBAIController(ROPRI.Squad.GetOwner(i));
		if (Mate != none && Mate.BBLastSmokeThrow > 0 && WorldInfo.TimeSeconds - Mate.BBLastSmokeThrow < 20.0)
		{
			return true;
		}
	}
	return false;
}

function bool BBTrySmoke()
{
	local ROObjective Obj;
	local vector Dir;
	local float Dist, R;

	if (WorldInfo.TimeSeconds < BBNextSmokeCheck || BBIsDefender() || !IsInState('GoThereAndStayThere'))
	{
		return false;
	}
	Obj = BBGetObjective(CurrentOrders.OrderIndex);
	if (Obj == none || !HasGrenade(ROWCT_SmokeGrenade))
	{
		return false;
	}
	R = BBObjectiveRadius(Obj);
	Dist = VSize(Pawn.Location - Obj.Location);
	if (Dist < R || Dist > R + 5000.0 || !BBSquadInContact() || BBSquadSmokedRecently())
	{
		return false;
	}
	// Nothing between us and the objective = open ground
	if (!FastTrace(Obj.Location + vect(0,0,100), Pawn.Location + vect(0,0,60)))
	{
		return false;
	}

	BBNextSmokeCheck = WorldInfo.TimeSeconds + 15.0;
	if (FRand() < 0.5)
	{
		return false;	// Not everyone thinks of it
	}

	BBLastSmokeThrow = WorldInfo.TimeSeconds;
	Dir = Obj.Location - Pawn.Location;
	Dir.Z = 0;
	ExplosiveTargetLocation = GetValidLocationNear(Pawn.Location + Normal(Dir) * BBRand(700, 1200), Pawn.Location);
	GrenadeToThrow = ROWCT_SmokeGrenade;
	PushState('ThrowGrenade');
	return true;
}

/*-----------------------------------------------------------------------------
	Combat tick
-----------------------------------------------------------------------------*/

function BBCombatTick()
{
	local bool bBusy;

	if (Pawn == none || Pawn.Health <= 0 || Vehicle(Pawn) != none || CurrentAIPurpose == AIP_VehicleAI ||
		!IsTerritoriesGame() || IsSuspended() || bDummyMode)
	{
		return;
	}

	BBUpdateMorale(0.5);
	BBUpdateSuppressionReaction();

	// ScanHorizon and our bound hold block overrides but are fine to interrupt
	bBusy = bCantOverrideState && !IsInState('ScanHorizon') && !IsInState('BBBoundHold');
	if (bBusy || HasExternalOrders() || IsInState('Mantling') || IsInState('MantlingUp') || IsInState('MantlingUpEnd'))
	{
		return;
	}

	if (BBTrySuppressiveFire() || BBTrySmoke())
	{
		return;
	}
	BBTryBound();
}

/*-----------------------------------------------------------------------------
	Stuck watchdog
-----------------------------------------------------------------------------*/

function bool BBCanCheckStuck()
{
	if (Pawn == none || Pawn.Health <= 0 || Pawn.Physics == PHYS_Falling || Vehicle(Pawn) != none)
	{
		return false;
	}
	if (!IsTerritoriesGame() || CurrentAIPurpose == AIP_VehicleAI || bDummyMode || IsSuspended() || HasExternalOrders())
	{
		return false;
	}
	// Fighting, or staying put on purpose (capture zone or role post)
	if (Enemy != none || IsEngageState() || InMyObjectiveArea(true) || BBIsHoldingPost())
	{
		return false;
	}
	// FlankRoute blocks overrides for its whole duration but can get stuck too
	if (bCantOverrideState && !IsInState('FlankRoute', true))
	{
		return false;
	}
	if (IsInState('Dead') || IsInState('BrainDead') || IsInState('Turreting') ||
		IsInState('ScriptedMove') || IsInState('ScriptedPatrol') || IsInState('ScriptedRoutePatrol') ||
		IsInState('Mantling') || IsInState('MantlingUp') || IsInState('MantlingUpEnd') ||
		IsInState('BuildTunnel') || IsInState('DestroySpawnTunnel') || IsInState('SetupTrap') ||
		IsInState('DisarmTrap') || IsInState('CallInAbility') || IsInState('ThrowSignalGrenade'))
	{
		return false;
	}
	return true;
}

function BBWatchdog()
{
	local float MovedSq;

	if (!BBCanCheckStuck())
	{
		BBStuckTicks = 0;
		if (Pawn != none)
		{
			BBLastWatchdogLocation = Pawn.Location;
		}
		return;
	}

	MovedSq = VSizeSq(Pawn.Location - BBLastWatchdogLocation);
	BBLastWatchdogLocation = Pawn.Location;

	if (MovedSq > BB_StuckDistSq)
	{
		BBStuckTicks = 0;
		BBStuckStrikes = 0;
		return;
	}

	BBStuckTicks++;
	if (BBStuckTicks < BB_StuckTicks)
	{
		return;
	}
	BBStuckTicks = 0;
	BBStuckStrikes++;

	if (BBStuckStrikes >= BB_StuckStrikesMax && CurrentOrders.OrderIndex >= 0)
	{
		`log("[BetterBots]"@GetPName()@"stuck going to objective"@CurrentOrders.OrderIndex$", trying another one");
		BBAvoidObjectiveIndex = CurrentOrders.OrderIndex;
		BBAvoidObjectiveUntil = WorldInfo.TimeSeconds + BB_AvoidTime;
		BBStuckStrikes = 0;
	}

	BBUnstick();
}

function BBUnstick()
{
	bCantOverrideState = false;
	if (bBBFlankStaging)
	{
		// Could not reach the staging point, go in from where we are
		bBBFlankStaging = false;
		bBBFlankStaged = true;
	}
	BBClearPost();	// The post may be unreachable
	ResetFailedMoveAttempts();
	EmptyPathCache();
	// Picks an objective (honouring the avoid list), a fresh goal point and restarts movement
	FindNewObjective();
}

defaultproperties
{
	BBAvoidObjectiveIndex=-1
	BBPostObjective=-1
	BBReinforceIndex=-1
}
