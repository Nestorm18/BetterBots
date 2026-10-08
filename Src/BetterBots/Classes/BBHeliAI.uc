//=============================================================================
// BBHeliAI
//=============================================================================
// Helicopter part of the bot controller (BBAIController extends this).
// The stock controller goes BrainDead in any vehicle; here bots fly, man
// door guns and turrets, and ride as passengers.
//
// Pilot missions (by helicopter, see BBHeliManager.HeliType):
//   Attack  (Cobra)      waits high and away, rocket/cannon runs on the best
//                        target, egress, repeat.
//   Scout   (Loach)      orbits the fight at varied (mostly medium) height,
//                        marks enemies on the map, short minigun runs.
//   Gunship (Bushranger) pylon-turn orbit so the door gunners can fire,
//                        rocket runs on anti-aircraft threats.
//   Lift    (Huey)       waits at base for passengers, flies to an LZ chosen
//                        by danger, unloads, comes back.
// All combat helis go home to rearm and repair when low on ammo, damaged or
// with a wounded crew, evade when hit, avoid remembered danger spots and try
// an emergency landing when a rotor or the engine is destroyed.
//
// Flight: a low-level autopilot (BBHeliSteer) holds a height over the
// terrain ahead with the collective, tracks a horizontal velocity with the
// cyclic (stock auto-hover law, tilt-limited) and a heading with the pedals.
// Mission logic (BBHeliThink, 4 times a second) only sets the nav target.
// UU: 50 per metre.
//=============================================================================

class BBHeliAI extends ROAIController
	config(Game);

// Nav modes for the autopilot
const NAV_Ground	= 0;	// Collective down, no cyclic
const NAV_Hold		= 1;	// Hover over BBNavPoint at BBNavAGL
const NAV_Move		= 2;	// Fly to BBNavPoint at BBNavSpeed, BBNavAGL over the ground ahead
const NAV_Vel		= 3;	// Fly at velocity BBNavVel, BBNavAGL over the ground ahead
const NAV_Descend	= 4;	// Hold BBNavPoint and come down gently

const BB_HeliHoverAGL		= 1500.0;	// 30 m
const BB_HeliLoiterAGL		= 2500.0;	// 50 m
const BB_HeliCruiseAGL		= 3000.0;	// 60 m over the highest ground ahead
const BB_HeliApproachAGL	= 1500.0;
const BB_HeliCruiseSpeed	= 2700.0;	// UU/s (~195 km/h)
const BB_HeliMaxTilt		= 4551.0;	// 25 deg cyclic limit
const BB_HeliAttackTilt		= 5461.0;	// 30 deg nose down while aiming
const BB_HeliRunSpeed		= 2400.0;
const BB_BoardDist			= 550.0;	// Close enough to climb in (11 m from the heli's centre)
const BB_HeliClimbRate		= 450.0;	// UU/s we can count on climbing at
const BB_HeliAASafeAGL		= 2500.0;	// 50 m: enemy SAMs only lock helis above 75 m

// Crew assignment (set by BBHeliManager)
var		ROVehicleHelicopter	BBCrewHeli;
var		int					BBCrewSeat;
var		float				BBCrewAssignTime;
var		BBHeliManager		BBHM;

// Pilot
var		bool				bBBHeliPilot;
var		ROVehicleHelicopter	BBHeli;
var		name				BBHeliMission;		// Test, Goto, Attack, Scout, Gunship, Lift
var		name				BBHeliTask;
var		float				BBHeliTaskStart;
var		float				BBHeliFlightStart;
var		float				BBHeliCollectiveTrim;
var		int					BBHeliTargetYaw;
var		vector				BBHeliHome;
var		vector				BBHeliDest;
var		vector				BBHeliLandPoint;
var		vector				BBHeliHoldPoint;
var		float				BBHeliLoiterTime;
var		float				BBHeliTerrainZ;
var		float				BBHeliNextTerrain;
var		float				BBHeliObstacleUntil;
var		float				BBHeliTerrainSpeedCap;
var		bool				bBBHeliAAWarned;
var		float				BBHeliNextLog;
var		float				BBHeliMaxAGL;
var		float				BBHeliTouchdownVZ;
var		float				BBHeliNextThink;
var		bool				bBBHeliCede;		// Flying home to give the pilot role to the human
var		bool				bBBHeliResume;
var		int					BBHeliLastYaw;
var		bool				bBBHeliLongShot;	// This attack is a long-range shot from a near hover
var		float				BBHeliLongDist;
var		bool				bBBHeliRunRockets;
var		float				BBHeliAimLift;		// Aim above the target for drop at long range

// Adaptive tactics: 0 = diving pass, 1 = long-range shot
var		byte				BBHeliTactic;
var		bool				bBBHeliTacticSet;
var		int					BBHeliTacticRuns[2];
var		int					BBHeliTacticKills[2];
var		int					BBHeliRunKills;		// Kills since the last attack started
var		int					BBHeliDryRuns;		// Attacks in a row without kills
var		bool				bBBHeliHadRun;
var		float				BBHeliNextTacticReview;
var		float				BBHeliNextStrikeCall;	// Rate limit for "attack whoever shot me" requests		// Re-entering BBHeliFly after a stray state change
var		vector				BBHeliStandoffCenter;

// Autopilot target
var		byte				BBNavMode;
var		vector				BBNavPoint;
var		vector				BBNavVel;
var		float				BBNavAGL;
var		float				BBNavSpeed;
var		bool				bBBNavFixedYaw;
var		bool				bBBNavAim;			// Point the gun socket at BBHeliTargetLoc
var		int					BBNavYaw;

// Combat
var		Pawn				BBHeliTarget;
var		vector				BBHeliTargetLoc;
var		vector				BBHeliCenter;
var		float				BBHeliNextCenter;
var		vector				BBHeliStandoff;
var		float				BBHeliStandoffAGL;
var		float				BBHeliOrbitRadius;
var		float				BBHeliOrbitAGL;
var		float				BBHeliOrbitDir;
var		float				BBHeliNextVary;
var		float				BBHeliNextRun;
var		float				BBHeliNextTargetPick;
var		int					BBHeliRunAmmoStart;
var		int					BBHeliRunAltAmmoStart;
var		bool				bBBHeliFiring;
var		byte				BBHeliFireMode;
var		float				BBHeliFireEnd;
var		float				BBHeliNextShot;
var		name				BBHeliResumeTask;
var		float				BBHeliEvadeUntil;
var		vector				BBHeliEvadeVel;
var		float				BBHeliNextSpot;
var		int					BBHeliLastHealth;
var		float				BBHeliRecentDamage;
var		float				BBHeliLegDamage;
var		vector				BBHeliWaypoint;
var		bool				bBBHeliHasWaypoint;
var		float				BBHeliNextRoute;

// Transport
var		vector				BBHeliLZ;
var		float				BBHeliNextLZTry;
var		float				BBHeliLZExtra;
var		float				BBHeliHumanAboardSince;
var		float				BBHeliNextWaitMsg;

// Waiting at base for a human who may still swap helis
var		float				BBHeliHoldStart;
var		float				BBHeliSeatedSince;

// Walking to a heli seat
var		float				BBBoardWalkStart;
var		float				BBBoardNextGoal;
var		float				BBBoardBestDist;
var		float				BBBoardProgressTime;
var		bool				bBBRideHumanPilot;

// Respawn selection pointed at a heli by the manager
var		bool				bBBHeliSpawnSel;
var		byte				BBSavedSpawnSel;
var		bool				bBBSpawnRolled;
var		bool				bBBSpawnInHeli;
var		int					BBSpawnFwdPick;

// Riders and gunners
var		bool				bBBHeliRider;
var		bool				bBBHeliGunner;
var		ROVehicleHelicopter	BBRideHeli;
var		int					BBRideSeat;
var		float				BBRideStart;
var		Pawn				BBGunTarget;
var		float				BBGunNextPick;
var		float				BBGunAimStart;
var		float				BBGunBurstEnd;
var		float				BBGunNextBurst;
var		bool				bBBGunFiring;
var		byte				BBGunMode;

/*-----------------------------------------------------------------------------
	Common
-----------------------------------------------------------------------------*/

function BBHeliManager BBGetHM()
{
	if (BBHM == none)
	{
		BBHM = class'BBHeliManager'.static.Get(WorldInfo);
	}
	return BBHM;
}

function string BBName()
{
	return (PlayerReplicationInfo != none) ? PlayerReplicationInfo.PlayerName : string(Name);
}

function ROVehicleHelicopter BBCurrentHeli()
{
	if (ROVehicleHelicopter(Pawn) != none)
	{
		return ROVehicleHelicopter(Pawn);
	}
	if (ROWeaponPawn(Pawn) != none)
	{
		return ROVehicleHelicopter(ROWeaponPawn(Pawn).MyVehicle);
	}
	return none;
}

function bool BBIsFlyingHeli()
{
	return bBBHeliPilot && BBHeli != none && BBHeli.Health > 0 && Pawn == BBHeli;
}

function Possess(Pawn aPawn, bool bVehicleTransition)
{
	local ROWeaponPawn WP;

	// The stock code never resets this after leaving a vehicle
	if (Vehicle(aPawn) == none && CurrentAIPurpose == AIP_VehicleAI)
	{
		CurrentAIPurpose = AIP_Combatant;
	}

	super.Possess(aPawn, bVehicleTransition);

	WP = ROWeaponPawn(aPawn);
	if (ROVehicleHelicopter(aPawn) != none && bBBHeliPilot)
	{
		BBHeli = ROVehicleHelicopter(aPawn);
		GotoState('BBHeliFly');
	}
	else if (WP != none && ROVehicleHelicopter(WP.MyVehicle) != none && !bBBHeliPilot)
	{
		if (!bBBHeliRider)
		{
			// Spawned straight into a seat (heli spawn)
			bBBHeliRider = true;
			bBBHeliGunner = class'BBHeliManager'.static.IsDoorGunSeat(ROVehicleHelicopter(WP.MyVehicle), WP.MySeatIndex) ||
				class'BBHeliManager'.static.IsGunnerCopilotSeat(ROVehicleHelicopter(WP.MyVehicle), WP.MySeatIndex);
			`log("[BetterBots][Heli]"@BBName()@"spawned in the"@class'BBHeliManager'.static.HeliName(ROVehicleHelicopter(WP.MyVehicle))@
				"seat"@WP.MySeatIndex@(bBBHeliGunner ? "as gunner" : "as passenger"));
		}
		GotoState('BBHeliRide');
	}
	else if (Vehicle(aPawn) == none)
	{
		bBBHeliPilot = false;
		bBBHeliRider = false;
		bBBHeliGunner = false;
		BBHeli = none;
		BBRideHeli = none;
		if (BBCrewHeli != none)
		{
			// Assigned while dead: get in once spawned
			SetTimer(1.0 + FRand(), false, 'BBTryBoardCrew');
		}
	}
}

function class<RORoleInfo> BBFindPilotRoleClass(bool bTransport)
{
	return (BBGetHM() != none) ? BBHM.PilotRoleClass(GetTeamNum(), bTransport) : none;
}

/** Gets this bot off the helicopter roles, back to infantry */
function BBFreePilotRole()
{
	local ROPlayerReplicationInfo ROPRI;

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	BBCrewHeli = none;
	if (ROPRI != none && ROPRI.RoleInfo != none && ROPRI.RoleInfo.bIsPilot)
	{
		if (ChooseRole())
		{
			ChooseSquad();
		}
		`log("[BetterBots][Heli]"@BBName()@"back to infantry role"@((ROPRI.RoleInfo != none) ? ROPRI.RoleInfo.Class : none));
	}
}

/*-----------------------------------------------------------------------------
	Boarding
-----------------------------------------------------------------------------*/

function BBSetCrewAssignment(ROVehicleHelicopter H, int Seat)
{
	BBCrewHeli = H;
	BBCrewSeat = Seat;
	BBCrewAssignTime = WorldInfo.TimeSeconds;
	if (Pawn != none && Pawn.Health > 0 && Vehicle(Pawn) == none)
	{
		SetTimer(0.5 + FRand(), false, 'BBTryBoardCrew');
	}
}

function BBTryBoardCrew()
{
	local ROVehicleHelicopter H;
	local int Seat;

	H = BBCrewHeli;
	Seat = BBCrewSeat;
	if (H == none || BBGetHM() == none || !BBHM.HeliUsable(H) || Pawn == none || Pawn.Health <= 0 || Vehicle(Pawn) != none)
	{
		BBCrewHeli = none;
		return;
	}
	if (!BBHM.SeatFree(H, Seat))
	{
		// Someone else got there first: back to infantry, the slot is needed
		BBCrewHeli = none;
		if (Seat == 0 || BBHM.IsGunnerCopilotSeat(H, Seat))
		{
			BBFreePilotRole();
		}
		return;
	}
	// Never jump into a heli in the air: wait for it to land (up to 90 s)
	if (!BBHM.HeliOnGround(H))
	{
		if (WorldInfo.TimeSeconds - BBCrewAssignTime < 90.0)
		{
			SetTimer(2.0, false, 'BBTryBoardCrew');
		}
		else
		{
			BBCrewHeli = none;
		}
		return;
	}
	// Spawned somewhere unrelated: forget it (keeps the role, the manager
	// prefers bots that already have it)
	if (VSize(Pawn.Location - H.Location) > 10000.0)
	{
		`log("[BetterBots][Heli]"@BBName()@"spawned too far from its"@BBHM.HeliName(H)$", assignment dropped");
		BBCrewHeli = none;
		return;
	}

	// Walk over to it (no teleporting into a heli from across the pad)
	if (VSize(Pawn.Location - H.Location) > BB_BoardDist && VSize(Pawn.Location - H.Location) < 2000.0)
	{
		BBBoardWalkStart = WorldInfo.TimeSeconds;
		BBBoardBestDist = VSize(Pawn.Location - H.Location);
		BBBoardProgressTime = WorldInfo.TimeSeconds;
		BBBoardNextGoal = 0;
		SetTimer(0.4, true, 'BBBoardWalkTick');
		BBBoardWalkTick();
		return;
	}
	BBBoardCrewNow(H, Seat);
}

function BBBoardCrewNow(ROVehicleHelicopter H, int Seat)
{
	BBCrewHeli = none;
	if (Seat == 0)
	{
		BBStartHeli(H, BBHM.HeliType(H), vect(0,0,0), 0);
	}
	else
	{
		BBBoardAsRider(H, Seat);
	}
}

function BBBoardWalkTick()
{
	local ROVehicleHelicopter H;
	local int Seat;
	local bool bAbort;
	local float D;

	H = BBCrewHeli;
	Seat = BBCrewSeat;
	if (H == none || Pawn == none || Pawn.Health <= 0 || Vehicle(Pawn) != none || BBGetHM() == none)
	{
		ClearTimer('BBBoardWalkTick');
		return;
	}
	bAbort = !BBHM.HeliUsable(H) || !BBHM.SeatFree(H, Seat) || !BBHM.HeliOnGround(H);
	if (bAbort)
	{
		ClearTimer('BBBoardWalkTick');
		`log("[BetterBots][Heli]"@BBName()@"gave up walking to the"@BBHM.HeliName(H));
		BBCrewHeli = none;
		if ((Seat == 0 || BBHM.IsGunnerCopilotSeat(H, Seat)) && !BBHM.SeatFree(H, Seat))
		{
			BBFreePilotRole();
		}
		if (IsInState('GoThereAndStayThere'))
		{
			GotoState('FindNextState');
		}
		return;
	}
	D = VSize(Pawn.Location - H.Location);
	if (D < BBBoardBestDist - 100.0)
	{
		BBBoardBestDist = D;
		BBBoardProgressTime = WorldInfo.TimeSeconds;
	}
	// There, or no path / stuck on the pad (3 s without getting closer, 20 s at most): climb in
	if (D < BB_BoardDist || WorldInfo.TimeSeconds - BBBoardProgressTime > 3.0 || WorldInfo.TimeSeconds - BBBoardWalkStart > 20.0)
	{
		ClearTimer('BBBoardWalkTick');
		if (IsInState('GoThereAndStayThere'))
		{
			GotoState('FindNextState');
		}
		BBBoardCrewNow(H, Seat);
		return;
	}
	// Keep heading there (combat may have pulled us into another state)
	if (WorldInfo.TimeSeconds > BBBoardNextGoal || !IsInState('GoThereAndStayThere'))
	{
		BBBoardNextGoal = WorldInfo.TimeSeconds + 3.0;
		Pawn.ShouldProne(false);
		SetGoalLocation(H.Location);
		if (!IsInState('GoThereAndStayThere'))
		{
			GotoState('GoThereAndStayThere');
		}
	}
}

/** Passenger or gunner seat */
function bool BBBoardAsRider(ROVehicleHelicopter H, int Seat)
{
	if (Pawn == none || Vehicle(Pawn) != none)
	{
		return false;
	}
	bBBHeliRider = true;
	bBBHeliGunner = class'BBHeliManager'.static.IsDoorGunSeat(H, Seat) || class'BBHeliManager'.static.IsGunnerCopilotSeat(H, Seat);
	Pawn.ShouldProne(false);
	if (!H.PassengerEnter(Pawn, Seat))
	{
		`log("[BetterBots][Heli] PassengerEnter refused for"@BBName()@"seat"@Seat);
		bBBHeliRider = false;
		bBBHeliGunner = false;
		return false;
	}
	`log("[BetterBots][Heli]"@BBName()@"boarded"@class'BBHeliManager'.static.HeliName(H)@"seat"@Seat@(bBBHeliGunner ? "as gunner" : "as passenger"));
	return true;
}

/**
 * Makes this bot a pilot and puts it in the helicopter's pilot seat.
 * Missions: Test (hover and land), Goto (fly to Dest and back), Home,
 * Attack, Scout, Gunship, Lift.
 */
function bool BBStartHeli(ROVehicleHelicopter Heli, name Mission, vector Dest, float LoiterSeconds)
{
	local ROPlayerReplicationInfo ROPRI;
	local class<RORoleInfo> PilotClass;

	ROPRI = ROPlayerReplicationInfo(PlayerReplicationInfo);
	if (ROPRI == none || Pawn == none || Heli == none || Vehicle(Pawn) != none)
	{
		return false;
	}

	if (ROPRI.RoleInfo == none || !ROPRI.RoleInfo.bIsPilot || ROPRI.RoleInfo.bIsTransportPilot != Heli.bTransportHelicopter)
	{
		PilotClass = BBFindPilotRoleClass(Heli.bTransportHelicopter);
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
	bBBHeliCede = false;
	bBBHeliResume = false;
	BBHeliMission = Mission;
	BBHeliDest = Dest;
	BBHeliLoiterTime = LoiterSeconds;
	Pawn.ShouldProne(false);
	if (!Heli.DriverEnter(Pawn))
	{
		`log("[BetterBots][Heli] DriverEnter refused for"@ROPRI.PlayerName@"in"@Heli);
		bBBHeliPilot = false;
		return false;
	}
	`log("[BetterBots][Heli]"@ROPRI.PlayerName@"is flying"@class'BBHeliManager'.static.HeliName(Heli)@"mission"@Mission);
	return true;
}

function bool BBStartHeliTest(ROVehicleHelicopter Heli, float HoverSeconds)
{
	return BBStartHeli(Heli, 'Test', vect(0,0,0), HoverSeconds);
}

/** New orders from the test console commands */
function BBHeliRetask(name Mission, vector Dest, float LoiterSeconds)
{
	BBHeliMission = Mission;
	BBHeliDest = Dest;
	BBHeliLoiterTime = LoiterSeconds;
	BBHeliStopFire();
	if (BBHeliTask == 'Spool' || BBHeliTask == 'Landed' || BBHeliTask == 'Done' || BBHeliTask == 'Wait' || BBHeliTask == 'Rearm')
	{
		BBHeliSetTask('Spool');
	}
	else
	{
		BBHeliStartMission();
	}
	`log("[BetterBots][Heli] Retasked:"@Mission@"dest"@Dest);
}

/** Return to base and leave the cockpit to the human */
function BBHeliStartCede()
{
	if (!BBIsFlyingHeli())
	{
		BBHeliGiveUp(true);
		return;
	}
	bBBHeliCede = true;
	BBHeliStopFire();
	BBHeliSetTask('RTB');
	BBHeliTellPassengers("[BetterBots] Volvemos a base: el piloto cede el helicoptero");
}

/** Leave the heli (if landed) and stop being a pilot */
function BBHeliGiveUp(bool bForHuman)
{
	local ROVehicleHelicopter H;

	H = BBCurrentHeli();
	if (H != none && bBBHeliPilot)
	{
		if (BBGetHM() != none && !BBHM.HeliOnGround(H))
		{
			BBHeliStartCede();
			return;
		}
		BBHeliLeaveHeli(true);
	}
	else if (H != none)
	{
		BBLeaveVehicle();
		BBFreePilotRole();
	}
	else
	{
		BBFreePilotRole();
	}
}

function BBHeliLeaveHeli(bool bFreeRole)
{
	local ROVehicleHelicopter H;

	H = BBHeli;
	BBHeliStopFire();
	bBBHeliPilot = false;
	if (H != none && Pawn == H)
	{
		H.SetHeloInputs(0, 0, 0, 0, 0, 0);
		if (!H.DriverLeave(true))
		{
			`log("[BetterBots][Heli]"@BBName()@"could not leave the heli");
		}
	}
	`log("[BetterBots][Heli]"@BBName()@"left the"@class'BBHeliManager'.static.HeliName(H));
	BBHeli = none;
	if (bFreeRole)
	{
		BBFreePilotRole();
	}
	if (Vehicle(Pawn) == none && !IsInState('FindNextState'))
	{
		GotoState('FindNextState');
	}
}

function BBLeaveVehicle()
{
	local Vehicle V;

	V = Vehicle(Pawn);
	BBGunStop();
	bBBHeliRider = false;
	bBBHeliGunner = false;
	BBRideHeli = none;
	if (V != none)
	{
		V.DriverLeave(true);
	}
	if (Vehicle(Pawn) == none)
	{
		GotoState('FindNextState');
	}
}

function BBHeliTellPassengers(string Msg)
{
	local int i;
	local PlayerController PC;

	if (BBHeli == none)
	{
		return;
	}
	for (i = 1; i < BBHeli.Seats.Length; i++)
	{
		PC = PlayerController(class'BBHeliManager'.static.SeatController(BBHeli, i));
		if (PC != none)
		{
			PC.ClientMessage(Msg);
		}
	}
}

/*-----------------------------------------------------------------------------
	Terrain helpers
-----------------------------------------------------------------------------*/

/** Height of the ground below a point (world geometry only) */
function float BBHeliGroundZ(vector P)
{
	local vector HitLocation, HitNormal, Start, End;

	Start = P;
	Start.Z = BBHeli.Location.Z + 8000.0;
	End = P;
	End.Z = BBHeli.Location.Z - 60000.0;
	if (!BBTraceSurface(Start, End, HitLocation, HitNormal))
	{
		return End.Z;
	}
	return HitLocation.Z;
}

/** First solid ground OR water surface below Start (water counts as ground for a heli) */
function bool BBTraceSurface(vector Start, vector End, out vector HitLocation, out vector HitNormal)
{
	local Actor HitActor;
	local vector HL, HN;

	foreach TraceActors(class'Actor', HitActor, HL, HN, End, Start,,, TRACEFLAG_PhysicsVolumes)
	{
		if (HitActor.bWorldGeometry || (PhysicsVolume(HitActor) != none && PhysicsVolume(HitActor).bWaterVolume))
		{
			HitLocation = HL;
			HitNormal = HN;
			return true;
		}
	}
	return false;
}

/** Height above ground under the helicopter, in UU */
function float BBHeliAGL()
{
	local vector HitLocation, HitNormal;

	if (!BBTraceSurface(BBHeli.Location, BBHeli.Location - vect(0,0,60000), HitLocation, HitNormal))
	{
		return 60000.0;
	}
	return BBHeli.Location.Z - HitLocation.Z - BBHeli.AltitudeOffset;
}

/** Height limited by the map ceiling */
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
function float BBHeliTerrainTargetZ(vector Dir, float Speed, float MaxLook, float WantedAGL)
{
	local float Step, D, GroundZ, MaxGround, Look, Rise;
	local int i;

	if (WorldInfo.TimeSeconds < BBHeliNextTerrain)
	{
		return BBHeliTerrainZ;
	}
	BBHeliNextTerrain = WorldInfo.TimeSeconds + 0.25;

	// Look ~8 s ahead: big ridges need time to climb over at our climb rate
	Look = FMin(FMax(Speed * 8.0, 3000.0), MaxLook + 2000.0);
	Step = Look / 8.0;
	MaxGround = BBHeliGroundZ(BBHeli.Location);
	BBHeliTerrainSpeedCap = 100000.0;
	for (i = 1; i <= 8; i++)
	{
		D = Step * i;
		GroundZ = BBHeliGroundZ(BBHeli.Location + Dir * D);
		MaxGround = FMax(MaxGround, GroundZ);
		// Too steep to climb at this speed: slow down so the climb fits (plus a margin to brake)
		Rise = GroundZ + BBHeli.AltitudeOffset + 0.6 * BBHeliClampAGL(WantedAGL) - BBHeli.Location.Z;
		if (Rise > 0)
		{
			BBHeliTerrainSpeedCap = FMin(BBHeliTerrainSpeedCap, FMax(D / (Rise / BB_HeliClimbRate + 2.5), 250.0));
		}
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

function float BBHeliDist2D(vector P)
{
	return VSize2D(P - BBHeli.Location);
}

function BBHeliSetTask(name NewTask)
{
	if (NewTask == BBHeliTask)
	{
		return;
	}
	`log("[BetterBots][Heli]"@BBName()@BBHeliMission@"task"@BBHeliTask@"->"@NewTask@"after"@int(WorldInfo.TimeSeconds - BBHeliTaskStart)$"s");
	BBHeliTask = NewTask;
	BBHeliTaskStart = WorldInfo.TimeSeconds;
	BBHeliLegDamage = 0;
	bBBHeliHasWaypoint = false;
	BBHeliNextRoute = 0;
	BBHeliHoldPoint = BBHeli.Location;
}

function float BBHeliTaskTime()
{
	return WorldInfo.TimeSeconds - BBHeliTaskStart;
}

/*-----------------------------------------------------------------------------
	Autopilot
-----------------------------------------------------------------------------*/

function BBNavGround()
{
	BBNavMode = NAV_Ground;
	bBBNavAim = false;
	bBBNavFixedYaw = false;
}

function BBNavHold(vector P, float AGL)
{
	BBNavMode = NAV_Hold;
	BBNavPoint = P;
	BBNavAGL = AGL;
	bBBNavAim = false;
	bBBNavFixedYaw = false;
}

function BBNavMove(vector P, float AGL, float Speed)
{
	BBNavMode = NAV_Move;
	BBNavPoint = P;
	BBNavAGL = AGL;
	BBNavSpeed = Speed;
	bBBNavAim = false;
	bBBNavFixedYaw = false;
}

function BBNavVelocity(vector V, float AGL)
{
	BBNavMode = NAV_Vel;
	BBNavVel = V;
	BBNavVel.Z = 0;
	BBNavAGL = AGL;
	bBBNavAim = false;
	bBBNavFixedYaw = false;
}

function BBNavDescend(vector P)
{
	BBNavMode = NAV_Descend;
	BBNavPoint = P;
	bBBNavAim = false;
	bBBNavFixedYaw = false;
}

/**
 * Fly to P avoiding remembered danger spots with a single side waypoint.
 * Returns the distance left to P.
 */
function float BBNavRoute(vector P, float AGL, float Speed)
{
	local vector DangerLoc, Side, Dir;

	if (WorldInfo.TimeSeconds > BBHeliNextRoute && BBGetHM() != none)
	{
		BBHeliNextRoute = WorldInfo.TimeSeconds + 5.0;
		bBBHeliHasWaypoint = false;
		if (BBHeliDist2D(P) > 12000.0 && BBHM.BBDangerOnRoute(GetTeamNum(), BBHeli.Location, P, 5000.0, 40.0, DangerLoc))
		{
			Dir = P - BBHeli.Location;
			Dir.Z = 0;
			Dir = Normal(Dir);
			Side = vect(0,0,1) cross Dir;
			if (((DangerLoc - BBHeli.Location) dot Side) > 0)
			{
				Side = -Side;
			}
			BBHeliWaypoint = DangerLoc + Side * 8000.0;
			bBBHeliHasWaypoint = true;
			`log("[BetterBots][Heli]"@BBName()@"detours around danger at"@DangerLoc);
		}
		// Flying home: keep clear of the fighting even if nobody shot at us yet
		else if (BBHeliTask == 'RTB' && BBHeliDist2D(P) > 12000.0 &&
			BBHM.BBObjectiveOnRoute(BBHeli.Location, P, 7500.0, DangerLoc))
		{
			Dir = P - BBHeli.Location;
			Dir.Z = 0;
			Dir = Normal(Dir);
			Side = vect(0,0,1) cross Dir;
			// The side with less remembered danger
			if (BBHM.BBDanger(GetTeamNum(), DangerLoc + Side * 10000.0, 6000.0) > BBHM.BBDanger(GetTeamNum(), DangerLoc - Side * 10000.0, 6000.0))
			{
				Side = -Side;
			}
			BBHeliWaypoint = DangerLoc + Side * 10000.0;
			bBBHeliHasWaypoint = true;
			`log("[BetterBots][Heli]"@BBName()@"going home around the objective at"@DangerLoc);
		}
	}
	if (bBBHeliHasWaypoint)
	{
		if (BBHeliDist2D(BBHeliWaypoint) < 2000.0)
		{
			bBBHeliHasWaypoint = false;
		}
		else
		{
			BBNavMove(BBHeliWaypoint, AGL, Speed);
			return BBHeliDist2D(P);
		}
	}
	BBNavMove(P, AGL, Speed);
	return BBHeliDist2D(P);
}

/**
 * Transit height by type (Loach ~25 m, Huey/Bushranger ~40 m, Cobra ~60 m),
 * 10-20 m lower near the fighting or remembered danger.
 */
function float BBHeliCruiseAGL()
{
	local float AGL, Lower;

	switch (BBHeliMission)
	{
		case 'Scout':	AGL = 1250.0; break;
		case 'Lift':
		case 'Gunship':	AGL = 2000.0; break;
		default:		AGL = BB_HeliCruiseAGL;
	}
	if (BBGetHM() != none && BBHeliMission != 'Test' && BBHeliMission != 'Goto')
	{
		if (BBHM.BBFrontDistance(BBHeli.Location) < 20000.0)
		{
			Lower = 500.0;
		}
		if (BBHM.BBDanger(GetTeamNum(), BBHeli.Location, 8000.0) > 20.0)
		{
			Lower += 500.0;
		}
	}
	return FMax(AGL - Lower, 900.0);
}

/** Circle Center at Radius; Speed along the circle */
function BBNavOrbit(vector Center, float Radius, float Speed, float AGL)
{
	local vector ToC, Radial, Tangent, V;
	local float R;

	ToC = Center - BBHeli.Location;
	ToC.Z = 0;
	R = VSize(ToC);
	if (R < 1.0)
	{
		ToC = vect(1,0,0);
		R = 1.0;
	}
	Radial = ToC / R;
	Tangent = (Radial cross vect(0,0,1)) * BBHeliOrbitDir;
	V = Tangent * Speed + Radial * FClamp((R - Radius) * 0.4, -700.0, 700.0);
	BBNavVelocity(V, AGL);
}

/**
 * Nose pitch and heading that put the pilot's gun socket on Target.
 * Uses the socket's offset from the fuselage so rockets/minigun line up.
 */
function BBHeliAimAt(vector Target, out int AimYaw, out int AimPitch)
{
	local vector L;
	local rotator R, ToT;
	local int YawOffset, PitchOffset;

	ToT = Rotator(Target - BBHeli.Location);
	YawOffset = 0;
	PitchOffset = 0;
	if (BBHeli.Seats.Length > 0 && BBHeli.Seats[0].Gun != none)
	{
		BBHeli.Seats[0].Gun.GetFireStartLocationAndRotation(L, R);
		ToT = Rotator(Target - L);
		YawOffset = NormalizeRotAxis(R.Yaw - BBHeli.Rotation.Yaw);
		PitchOffset = NormalizeRotAxis(R.Pitch - BBHeli.Rotation.Pitch);
	}
	AimYaw = NormalizeRotAxis(ToT.Yaw - YawOffset);
	AimPitch = NormalizeRotAxis(ToT.Pitch - PitchOffset);
}

function BBHeliSteer(float DeltaTime)
{
	local vector X, Y, Z, VelNoZ, DesiredVel, VelErr, ToDest, Dir;
	local float AGL, VZ, DesiredVZ, TargetZ, Collective, SpeedNorm, TargetPitch, TargetRoll;
	local float InForward, InStrafe, InYaw, Dist, Speed, WantedSpeed, MaxClimb, YawRate;
	local int YawErr, AimYaw, AimPitch;
	local bool bAirborne, bAA;

	AGL = BBHeliAGL();
	VZ = BBHeli.Velocity.Z;
	VelNoZ = BBHeli.Velocity;
	VelNoZ.Z = 0;
	Speed = VSize(VelNoZ);
	BBHeliMaxAGL = FMax(BBHeliMaxAGL, AGL);
	MaxClimb = 500.0;
	bAirborne = (BBNavMode != NAV_Ground);
	bAA = bAirborne && BBHeliAAThreat();
	if (bAA)
	{
		// Enemy SAMs only lock helis above 75 m: stay at 50 m or lower
		BBNavAGL = FMin(BBNavAGL, BB_HeliAASafeAGL);
		if (!bBBHeliAAWarned)
		{
			bBBHeliAAWarned = true;
			`log("[BetterBots][Heli]"@BBName()@"enemy anti-air active, diving below radar from AGL"@int(AGL));
			BBHeliTellPassengers("[BetterBots] Antiaereo enemigo: bajamos ya");
		}
	}
	else
	{
		bBBHeliAAWarned = false;
	}

	switch (BBNavMode)
	{
		case NAV_Move:
			ToDest = BBNavPoint - BBHeli.Location;
			ToDest.Z = 0;
			Dist = VSize(ToDest);
			Dir = (Dist > 1.0) ? ToDest / Dist : vect(0,0,0);
			WantedSpeed = FMin(BBNavSpeed, FMax(Dist * 0.35, 120.0));
			TargetZ = BBHeliTerrainTargetZ(Dir, Speed, Dist, BBNavAGL);
			DesiredVel = Dir * WantedSpeed;
			if (Dist > 800.0)
			{
				BBNavYaw = Rotator(ToDest).Yaw;
			}
			break;

		case NAV_Vel:
			DesiredVel = BBNavVel;
			WantedSpeed = VSize(DesiredVel);
			Dir = (WantedSpeed > 1.0) ? DesiredVel / WantedSpeed : vect(0,0,0);
			TargetZ = BBHeliTerrainTargetZ(Dir, Speed, 6000.0, BBNavAGL);
			if (WantedSpeed > 300.0)
			{
				BBNavYaw = Rotator(DesiredVel).Yaw;
			}
			break;

		case NAV_Hold:
		case NAV_Descend:
			DesiredVel = (BBNavPoint - BBHeli.Location) * 0.5;
			DesiredVel.Z = 0;
			if (VSize(DesiredVel) > 300.0)
			{
				DesiredVel = Normal(DesiredVel) * 300.0;
			}
			TargetZ = BBHeliGroundZ(BBHeli.Location) + BBHeli.AltitudeOffset + BBHeliClampAGL(BBNavAGL);
			break;
	}

	// Obstacles ahead in the moving modes: slow right down and climb over
	if (BBNavMode == NAV_Move || BBNavMode == NAV_Vel)
	{
		if (BBHeliObstacleAhead(VelNoZ))
		{
			BBHeliObstacleUntil = WorldInfo.TimeSeconds + 3.0;
		}
		if (WorldInfo.TimeSeconds < BBHeliObstacleUntil)
		{
			DesiredVel *= 0.3;
			TargetZ += 1500.0;
			MaxClimb = 700.0;
		}
		else if (TargetZ - BBHeli.Location.Z > 800.0)
		{
			// Rising ground ahead: slow down while climbing
			DesiredVel *= 0.4;
		}
		if (VSize(DesiredVel) > BBHeliTerrainSpeedCap)
		{
			DesiredVel = Normal(DesiredVel) * BBHeliTerrainSpeedCap;
		}
		TargetZ += BBHeliSeparate(DesiredVel);
	}

	// --- Collective ---
	if (!bAirborne)
	{
		Collective = 0.0;
	}
	else
	{
		if (BBNavMode == NAV_Descend)
		{
			// Brake well before the ground: the rotor loses RPM at high
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
		else if (bAA)
		{
			// Drop out of the SAM's radar as fast as the rotor allows (the target height is already capped)
			DesiredVZ = FClamp((TargetZ - BBHeli.Location.Z) * 0.8, (AGL > BB_HeliAASafeAGL + 800.0) ? -1100.0 : -350.0, MaxClimb);
		}
		else
		{
			DesiredVZ = FClamp((TargetZ - BBHeli.Location.Z) * 0.8, -350.0, MaxClimb);
		}
		// Learn the hover point slowly (it changes with speed), then a proportional term
		BBHeliCollectiveTrim = FClamp(BBHeliCollectiveTrim + 0.0005 * (DesiredVZ - VZ) * DeltaTime, 0.4, 0.98);
		Collective = FClamp(BBHeliCollectiveTrim + 0.0015 * (DesiredVZ - VZ), 0.0, 1.0);
	}

	// --- Cyclic and pedals ---
	if (bAirborne)
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

		if (bBBNavAim)
		{
			// Point the guns: nose on the target
			BBHeliAimAt(BBHeliTargetLoc + vect(0,0,1) * BBHeliAimLift, AimYaw, AimPitch);
			BBNavYaw = AimYaw;
			TargetPitch = FClamp(AimPitch, -BB_HeliAttackTilt, BB_HeliMaxTilt * 0.5);
		}
		else if (bBBNavFixedYaw)
		{
			// Keep the heading the mission asked for
		}

		InForward = FClamp((BBHeli.CurrentPitch - TargetPitch) / BBHeli.MaxAutoHoverPitch, -1.0, 1.0);
		InStrafe = FClamp((BBHeli.CurrentRoll - TargetRoll) / BBHeli.MaxAutoHoverRoll, -1.0, 1.0);

		BBHeliTargetYaw = BBNavYaw;
		YawErr = NormalizeRotAxis(BBHeliTargetYaw - BBHeli.Rotation.Yaw);
		// Pedals: proportional plus yaw-rate damping (stronger when aiming)
		YawRate = NormalizeRotAxis(BBHeli.Rotation.Yaw - BBHeliLastYaw) / FMax(DeltaTime, 0.001);
		if (bBBNavAim)
		{
			InYaw = FClamp(YawErr / 3000.0 - YawRate / 15000.0, -1.0, 1.0);
		}
		else
		{
			InYaw = FClamp(YawErr / 6000.0 - YawRate / 20000.0, -0.8, 0.8);
		}
	}

	BBHeliLastYaw = BBHeli.Rotation.Yaw;

	// The stock auto-hover would overwrite our cyclic inputs
	if (BBHeli.bAutoHover)
	{
		BBHeli.ToggleAutoHover();
	}
	BBHeli.SetHeloInputs(InForward, InStrafe, 0, 0, Collective, InYaw);

	if (WorldInfo.TimeSeconds >= BBHeliNextLog)
	{
		BBHeliNextLog = WorldInfo.TimeSeconds + 1.0;
		`log("[BetterBots][Heli]"@BBName()@BBHeliMission$"/"$BBHeliTask@"Nav="$BBNavMode@"AGL="$int(AGL)@"VZ="$int(VZ)@"Spd="$int(Speed)@
			"Dist="$int(Dist)@"dZ="$int(TargetZ - BBHeli.Location.Z)@"RPM="$int(BBHeli.CurrentRPM)$"/"$int(BBHeli.NormalRPM)@
			"Coll="$Collective@"Trim="$BBHeliCollectiveTrim@"Pitch="$int(BBHeli.CurrentPitch * 0.0055)@"Roll="$int(BBHeli.CurrentRoll * 0.0055)@
			"YawErr="$int(YawErr * 0.0055)@"Obst="$(WorldInfo.TimeSeconds < BBHeliObstacleUntil)@"HP="$BBHeli.Health@
			"Aim="$bBBNavAim@"Fire="$bBBHeliFiring);
	}
}

/*-----------------------------------------------------------------------------
	Pilot weapons
-----------------------------------------------------------------------------*/

function ROVehicleWeapon BBHeliGun()
{
	if (BBHeli != none && BBHeli.Seats.Length > 0)
	{
		return BBHeli.Seats[0].Gun;
	}
	return none;
}

function bool BBHeliHasAmmo(byte Mode)
{
	local ROVehicleWeapon G;

	G = BBHeliGun();
	if (G == none)
	{
		return false;
	}
	if (Mode == 0)
	{
		return G.AmmoCount > 0;
	}
	return G.MaxAltAmmoCount > 0 && G.AltAmmoCount > 0;
}

/** Fire the pilot's weapon at T if it is lined up, in range and safe */
function bool BBHeliTryFire(vector T, float MinDist, float MaxDist, float MinDot, byte Mode, float Burst)
{
	local ROVehicleWeapon G;
	local vector L;
	local rotator R;
	local float D;

	G = BBHeliGun();
	if (G == none || bBBHeliFiring || WorldInfo.TimeSeconds < BBHeliNextShot || !BBHeliHasAmmo(Mode) || BBGetHM() == none)
	{
		return false;
	}
	G.GetFireStartLocationAndRotation(L, R);
	D = VSize(T - L);
	if (D < MinDist || D > MaxDist || (Normal(T - L) dot Vector(R)) < MinDot)
	{
		return false;
	}
	if (BBHM.BBFriendliesNear(GetTeamNum(), T, 2500.0) || !FastTrace(T + vect(0,0,40), L))
	{
		return false;
	}
	if (!BBHeli.AIFireWeapon(0, T, Mode))
	{
		return false;
	}
	bBBHeliFiring = true;
	BBHeliFireMode = Mode;
	BBHeliFireEnd = WorldInfo.TimeSeconds + Burst;
	return true;
}

function BBHeliStopFire()
{
	if (bBBHeliFiring && BBHeli != none)
	{
		BBHeli.AIEndFireWeapon(0, BBHeliFireMode);
		BBHeliNextShot = WorldInfo.TimeSeconds + ((BBHeliFireMode == 0 && BBHeliMission != 'Scout') ? 0.35 : 0.8);
	}
	bBBHeliFiring = false;
}

function BBHeliFireTick()
{
	if (bBBHeliFiring)
	{
		BBHeli.currAimPt = BBHeliTargetLoc + vect(0,0,1) * BBHeliAimLift;
		if (WorldInfo.TimeSeconds > BBHeliFireEnd)
		{
			BBHeliStopFire();
		}
	}
}

/*-----------------------------------------------------------------------------
	Damage, rearm, danger
-----------------------------------------------------------------------------*/

function bool BBHeliIsCombatTask()
{
	return BBHeliTask == 'Standoff' || BBHeliTask == 'RunIn' || BBHeliTask == 'Egress' || BBHeliTask == 'Orbit' ||
		BBHeliTask == 'Transit' || BBHeliTask == 'Evade';
}

function BBHeliMonitorDamage(float DeltaTime)
{
	local int Dmg;
	local vector Src;

	BBHeliRecentDamage = FMax(0.0, BBHeliRecentDamage - DeltaTime * 8.0);
	if (BBHeliLastHealth <= 0)
	{
		BBHeliLastHealth = BBHeli.Health;
	}
	if (BBHeli.Health >= BBHeliLastHealth)
	{
		BBHeliLastHealth = BBHeli.Health;	// Repairs
		return;
	}

	Dmg = BBHeliLastHealth - BBHeli.Health;
	BBHeliLastHealth = BBHeli.Health;
	BBHeliRecentDamage += Dmg;
	BBHeliLegDamage += Dmg;

	if (BBHeli.LastHitBy != none && BBHeli.LastHitBy.Pawn != none && BBHeli.LastHitBy.GetTeamNum() != GetTeamNum())
	{
		Src = BBHeli.LastHitBy.Pawn.Location;
	}
	else
	{
		Src = BBHeli.Location;
		Src.Z = BBHeliGroundZ(Src);
	}
	if (BBGetHM() != none)
	{
		BBHM.BBAddThreat(GetTeamNum(), Src, Dmg);
	}
	`log("[BetterBots][Heli]"@BBName()@"hit for"@Dmg@"health"@BBHeli.Health@"from"@Src);

	// Known shooter: the Loach marks it, and every heli calls the attack helis on it
	if (BBHeli.LastHitBy != none && BBHeli.LastHitBy.Pawn != none && BBHeli.LastHitBy.GetTeamNum() != GetTeamNum() &&
		BBHeli.LastHitBy.Pawn.Health > 0 && WorldInfo.TimeSeconds > BBHeliNextStrikeCall && BBGetHM() != none)
	{
		BBHeliNextStrikeCall = WorldInfo.TimeSeconds + 5.0;
		if (BBHeliMission == 'Scout')
		{
			BBHM.BBAddMark(GetTeamNum(), BBHeli.LastHitBy.Pawn);
			AIDoEnemySpotted(BBHeli.LastHitBy.Pawn.Location, BBHeli.LastHitBy.Pawn);
		}
		BBHM.BBRequestStrike(BBHeli, BBHeli.LastHitBy.Pawn);
	}

	// Hit hard in combat: break away (shaken pilots sooner)
	if (BBHeliRecentDamage > 20.0 + 30.0 * FClamp(BBHeliMorale(), 0.0, 1.0) && BBHeliIsCombatTask() && BBHeliTask != 'Evade' && BBHeliMission != 'Lift' &&
		BBHeliMission != 'Test' && BBHeliMission != 'Goto')
	{
		BBHeliStartEvade(Src);
	}
}

function BBHeliStartEvade(vector From)
{
	local vector Away;

	Away = BBHeli.Location - From;
	Away.Z = 0;
	if (VSize(Away) < 1.0)
	{
		Away = -Vector(BBHeli.Rotation);
		Away.Z = 0;
	}
	Away = Normal(Away);
	// Break to one side, not straight away (harder to track)
	Away = Normal(Away + (vect(0,0,1) cross Away) * ((FRand() < 0.5) ? 0.7 : -0.7));
	BBHeliEvadeVel = Away * 2400.0;
	BBHeliEvadeUntil = WorldInfo.TimeSeconds + 4.0 + FRand() * 2.0;
	if (BBHeliTask != 'Evade')
	{
		BBHeliResumeTask = (BBHeliTask == 'RunIn' || BBHeliTask == 'Egress') ? 'Standoff' : BBHeliTask;
	}
	BBHeliStopFire();
	BBHeliSetTask('Evade');
}

function bool BBHeliCrewHurt()
{
	local int i, Seat;

	// Crew health lives in the seat proxies (0-100), not in the hidden driver pawns
	for (i = 0; i < BBHeli.SeatProxies.Length; i++)
	{
		Seat = BBHeli.SeatProxies[i].SeatIndex;
		if ((Seat == 0 || class'BBHeliManager'.static.IsGunnerCopilotSeat(BBHeli, Seat)) &&
			class'BBHeliManager'.static.SeatController(BBHeli, Seat) != none &&
			BBHeli.SeatProxies[i].Health > 0 && BBHeli.SeatProxies[i].Health < 50)
		{
			return true;
		}
	}
	return false;
}

function bool BBHeliAmmoLow()
{
	local ROVehicleWeapon G, DG;
	local int i;
	local bool bDoorsLow, bHasDoors;

	G = BBHeliGun();
	switch (BBHeliMission)
	{
		case 'Attack':
			if (G == none)
			{
				return false;
			}
			return G.AmmoCount <= G.MaxAmmoCount * 0.2 && (G.MaxAltAmmoCount <= 0 || G.AltAmmoCount <= G.MaxAltAmmoCount * 0.2);
		case 'Scout':
			return G != none && G.AmmoCount <= G.MaxAmmoCount * 0.2;
		case 'Gunship':
			bDoorsLow = true;
			for (i = 1; i < BBHeli.Seats.Length; i++)
			{
				if (class'BBHeliManager'.static.IsDoorGunSeat(BBHeli, i))
				{
					DG = BBHeli.Seats[i].Gun;
					if (DG != none)
					{
						bHasDoors = true;
						if (DG.AmmoCount > DG.MaxAmmoCount * 0.2)
						{
							bDoorsLow = false;
						}
					}
				}
			}
			return bHasDoors && bDoorsLow && (G == none || G.AmmoCount <= G.MaxAmmoCount * 0.2);
	}
	return false;
}

/** 0-1, overridden by BBAIController with the bot's courage (bravery + morale) */
function float BBHeliMorale()
{
	return 0.5;
}

function bool BBHeliNeedsRearm()
{
	local float HealthLimit;

	if (BBHeliMission != 'Attack' && BBHeliMission != 'Scout' && BBHeliMission != 'Gunship')
	{
		return false;
	}
	// Brave pilots stay until 40 % health, shaken ones head home at 70 %
	HealthLimit = 0.4 + 0.3 * (1.0 - FClamp(BBHeliMorale(), 0.0, 1.0));
	return BBHeliAmmoLow() || BBHeli.bEngineDamaged || BBHeli.bMainRotorDamaged || BBHeli.bTailRotorDamaged ||
		BBHeli.Health < BBHeli.HealthMax * HealthLimit || BBHeliCrewHurt();
}

function bool BBHeliEmergency()
{
	return BBHeli.bEngineDestroyed || BBHeli.bMainRotorDestroyed || BBHeli.bTailRotorDestroyed;
}

/*-----------------------------------------------------------------------------
	Mission logic
-----------------------------------------------------------------------------*/

function bool BBHeliNearHome()
{
	return BBHeliDist2D(BBHeliHome) < 3000.0;
}

function BBHeliRefreshCenter()
{
	if (WorldInfo.TimeSeconds < BBHeliNextCenter || BBGetHM() == none)
	{
		return;
	}
	BBHeliNextCenter = WorldInfo.TimeSeconds + 20.0;
	if (!BBHM.BBFightCenter(GetTeamNum(), BBHeliCenter))
	{
		BBHeliCenter = BBHeliHome;
	}
}

/** Waiting point for the Cobra: high, on our side, out of the remembered danger */
function BBHeliPickStandoff()
{
	local vector Dir, Cand, Best;
	local float MaxDist, D, Danger, BestDanger, Ang;
	local int i;

	Dir = BBHeliHome - BBHeliCenter;
	Dir.Z = 0;
	MaxDist = VSize(Dir) * 0.8;
	Dir = Normal(Dir);
	D = FMin(30000.0 + FRand() * 20000.0, FMax(MaxDist, 8000.0));	// 600-1000 m, inside the map
	BestDanger = 1000000.0;
	for (i = 0; i < 5; i++)
	{
		Ang = (FRand() - 0.5) * 1.4;
		Cand = BBHeliCenter + (Dir * Cos(Ang) + (vect(0,0,1) cross Dir) * Sin(Ang)) * D;
		Danger = (BBGetHM() != none) ? BBHM.BBDanger(GetTeamNum(), Cand, 8000.0) : 0.0;
		if (Danger < BestDanger)
		{
			BestDanger = Danger;
			Best = Cand;
		}
	}
	BBHeliStandoff = Best;
	BBHeliStandoffCenter = BBHeliCenter;
	BBHeliStandoffAGL = 4000.0 + FRand() * 2000.0;	// 80-120 m
}

/** Takeoff done (or new orders): start or resume the mission */
function BBHeliStartMission()
{
	if (bBBHeliCede || BBHeliMission == 'Home')
	{
		BBHeliSetTask('RTB');
		return;
	}
	if (BBHeliNeedsRearm() && !BBHeliNearHome())
	{
		BBHeliSetTask('RTB');
		return;
	}
	switch (BBHeliMission)
	{
		case 'Test':
			BBHeliSetTask('Hold');
			break;
		case 'Goto':
			BBHeliSetTask('Transit');
			break;
		case 'Attack':
			BBHeliNextCenter = 0;
			BBHeliRefreshCenter();
			BBHeliPickStandoff();
			BBHeliSetTask('Standoff');
			break;
		case 'Scout':
		case 'Gunship':
			BBHeliNextCenter = 0;
			BBHeliRefreshCenter();
			BBHeliOrbitDir = (FRand() < 0.5) ? 1.0 : -1.0;
			BBHeliVaryOrbit();
			BBHeliSetTask('Orbit');
			break;
		case 'Lift':
			if (BBHeliLZ != vect(0,0,0) && BBHeliDist2D(BBHeliLZ) > 3000.0 && BBHeliCarriesPassengers())
			{
				BBHeliSetTask('Transit');
			}
			else
			{
				BBHeliSetTask('RTB');
			}
			break;
		default:
			BBHeliSetTask('RTB');
	}
}

function bool BBHeliCarriesPassengers()
{
	local int NumHumans;

	return BBGetHM() != none && BBHM.NumPassengers(BBHeli, NumHumans) > 0;
}

function BBHeliVaryOrbit()
{
	BBHeliNextVary = WorldInfo.TimeSeconds + 15.0 + FRand() * 10.0;
	if (BBHeliMission == 'Scout')
	{
		// Mostly medium (30-50 m), sometimes lower or wider
		BBHeliOrbitAGL = (FRand() < 0.75) ? 1500.0 + FRand() * 1000.0 : 1000.0 + FRand() * 500.0;
		BBHeliOrbitRadius = 1800.0 + FRand() * 1700.0;
	}
	else
	{
		BBHeliOrbitAGL = 2000.0 + FRand() * 1000.0;
		BBHeliOrbitRadius = 2500.0 + FRand() * 1000.0;
	}
	if (FRand() < 0.3)
	{
		BBHeliOrbitDir *= -1.0;
	}
}

/** Loach: mark every enemy it can see (map markers for the team, targets for the Cobra) */
function BBHeliSpot()
{
	local Pawn P;
	local int NumSpotted;
	local vector Eye;

	if (WorldInfo.TimeSeconds < BBHeliNextSpot || BBGetHM() == none)
	{
		return;
	}
	BBHeliNextSpot = WorldInfo.TimeSeconds + 1.0;
	Eye = BBHeli.Location - vect(0,0,120);
	foreach WorldInfo.AllPawns(class'Pawn', P)
	{
		if (P.Health <= 0 || P.GetTeamNum() == GetTeamNum() || P.GetTeamNum() > 1 || ROVehicleHelicopter(P) != none ||
			P.DrivenVehicle != none || VSizeSq(P.Location - BBHeli.Location) > 81000000.0)	// 180 m
		{
			continue;
		}
		if (!FastTrace(P.Location + vect(0,0,40), Eye))
		{
			continue;
		}
		BBHM.BBAddMark(GetTeamNum(), P);
		if (NumSpotted < 3)
		{
			AIDoEnemySpotted(P.Location, P);
			NumSpotted++;
		}
	}
}

/** Picks a target for a gun run; true if one is worth attacking now */
function bool BBHeliFindRunTarget(float Range)
{
	if (WorldInfo.TimeSeconds < BBHeliNextTargetPick || BBGetHM() == none)
	{
		return false;
	}
	BBHeliNextTargetPick = WorldInfo.TimeSeconds + 1.5;
	BBHeliTarget = BBHM.BBPickAirTarget(BBHeli, BBHeliCenter, 9000.0, Range);
	if (BBHeliTarget == none)
	{
		return false;
	}
	BBHeliTargetLoc = BBHeliTarget.Location;
	return true;
}

/**
 * Keep the tactic that gets kills. Three attacks in a row without kills:
 * switch. Every 3-5 min compare kills per attack of both and keep the best,
 * sometimes trying the other one again.
 */
function BBHeliPickTactic()
{
	local float Rate0, Rate1;
	local byte Old;

	if (!bBBHeliTacticSet)
	{
		bBBHeliTacticSet = true;
		BBHeliTactic = (FRand() < ((BBHeliMission == 'Scout') ? 0.35 : 0.45)) ? 1 : 0;
		BBHeliNextTacticReview = WorldInfo.TimeSeconds + 180.0 + FRand() * 120.0;
		`log("[BetterBots][Heli]"@BBName()@"starts with tactic"@BBHeliTacticName(BBHeliTactic));
	}
	Old = BBHeliTactic;

	// How did the previous attack go?
	if (bBBHeliHadRun)
	{
		if (BBHeliRunKills > 0)
		{
			BBHeliDryRuns = 0;
		}
		else
		{
			BBHeliDryRuns++;
		}
	}
	BBHeliRunKills = 0;

	if (BBHeliDryRuns >= 3)
	{
		BBHeliTactic = 1 - BBHeliTactic;
		BBHeliDryRuns = 0;
		`log("[BetterBots][Heli]"@BBName()@"3 attacks without kills, switching to"@BBHeliTacticName(BBHeliTactic));
	}
	else if (WorldInfo.TimeSeconds > BBHeliNextTacticReview)
	{
		BBHeliNextTacticReview = WorldInfo.TimeSeconds + 180.0 + FRand() * 120.0;
		Rate0 = (BBHeliTacticKills[0] + 1.0) / (BBHeliTacticRuns[0] + 2.0);
		Rate1 = (BBHeliTacticKills[1] + 1.0) / (BBHeliTacticRuns[1] + 2.0);
		BBHeliTactic = (Rate1 > Rate0) ? 1 : 0;
		if (FRand() < 0.25)
		{
			BBHeliTactic = 1 - BBHeliTactic;	// Try the other one now and then
		}
		`log("[BetterBots][Heli]"@BBName()@"tactic review: pass"@BBHeliTacticKills[0]$"/"$BBHeliTacticRuns[0]@
			"long"@BBHeliTacticKills[1]$"/"$BBHeliTacticRuns[1]@"(kills/attacks) ->"@BBHeliTacticName(BBHeliTactic));
	}
	if (Old != BBHeliTactic)
	{
		BBHeliDryRuns = 0;
	}
	BBHeliTacticRuns[BBHeliTactic]++;
	bBBHeliHadRun = true;
}

function string BBHeliTacticName(byte T)
{
	return (T == 1) ? "long-range" : "pass";
}

/** Our helicopter weapons killed someone: credit the current tactic */
function NotifyKilled(Controller Killer, Controller Killed, Pawn KilledPawn, class<DamageType> damageType)
{
	super.NotifyKilled(Killer, Killed, KilledPawn, damageType);

	if (Killer == self && bBBHeliPilot && Killed != none && Killed != self && Killed.GetTeamNum() != GetTeamNum() && bBBHeliHadRun)
	{
		BBHeliRunKills++;
		BBHeliTacticKills[BBHeliTactic]++;
		`log("[BetterBots][Heli]"@BBName()@"kill with tactic"@BBHeliTacticName(BBHeliTactic)@
			"("$BBHeliTacticKills[BBHeliTactic]@"kills in"@BBHeliTacticRuns[BBHeliTactic]@"attacks)");
	}
}

/** A friendly heli is being shot: go after the shooter (attack helis with ammo) */
function bool BBHeliTakeStrike()
{
	local Pawn P;

	if ((BBHeliMission != 'Attack' && BBHeliMission != 'Gunship') || !(BBHeliHasAmmo(0) || BBHeliHasAmmo(1)) || BBGetHM() == none)
	{
		return false;
	}
	if (BBHeliMission == 'Gunship' && !BBHeliHasAmmo(0))
	{
		return false;
	}
	P = BBHM.BBTakeStrike(BBHeli, 45000.0);
	if (P == none)
	{
		return false;
	}
	BBHeliTarget = P;
	BBHeliTargetLoc = P.Location;
	`log("[BetterBots][Heli]"@BBName()@"answering a call: attacking the shooter"@P);
	BBHeliStartRun();
	return true;
}

function BBHeliStartRun()
{
	local ROVehicleWeapon G;

	G = BBHeliGun();
	BBHeliRunAmmoStart = (G != none) ? G.AmmoCount : 0;
	BBHeliRunAltAmmoStart = (G != none) ? G.AltAmmoCount : 0;
	BBHeliResumeTask = (BBHeliMission == 'Attack') ? 'Standoff' : 'Orbit';
	BBHeliAimLift = 0;

	// Two styles: a fast diving pass, or a long-range shot from a near hover
	// (steadier aim, out of small-arms range). Keeps what works, see BBHeliPickTactic
	BBHeliPickTactic();
	bBBHeliLongShot = (BBHeliTactic == 1);
	if (BBHeliMission == 'Scout')
	{
		BBHeliLongDist = 6000.0 + FRand() * 3000.0;		// 120-180 m
	}
	else
	{
		BBHeliLongDist = 15000.0 + FRand() * 12000.0;	// 300-540 m
	}

	// Rockets for fixed weapons and AA (or when the cannon is empty), else mostly the cannon
	bBBHeliRunRockets = BBHeliHasAmmo(0) && (BBHeliMission != 'Attack' || !BBHeliHasAmmo(1) || Vehicle(BBHeliTarget) != none ||
		(BBGetHM() != none && BBHeliTarget != none && BBHM.BBIsAirThreat(BBHeliTarget)) || FRand() < 0.3);

	`log("[BetterBots][Heli]"@BBName()@(bBBHeliLongShot ? "long-range shot" : "attack run")@"on"@BBHeliTarget@"at"@
		int(BBHeliDist2D(BBHeliTargetLoc))@"UU"@(bBBHeliRunRockets ? "rockets" : "guns"));
	BBHeliSetTask('RunIn');
}

/**
 * Attack: nose on the target, fire when lined up.
 * Pass: dive at it, then break off. Long shot: hold a firing point far out,
 * nearly hovering, and shoot from there.
 */
function BBHeliRunIn()
{
	local vector ToT, FirePoint;
	local float D, AGL, RunSpeed, MaxRange, TimeLimit;
	local ROVehicleWeapon G;
	local bool bDone;
	local int Fired, AimYaw, AimPitch;
	local vector AimLoc;

	if (BBHeliTarget != none && BBHeliTarget.Health > 0 && FastTrace(BBHeliTarget.Location + vect(0,0,40), BBHeli.Location - vect(0,0,150)))
	{
		BBHeliTargetLoc = BBHeliTarget.Location + vect(0,0,20);
	}
	ToT = BBHeliTargetLoc - BBHeli.Location;
	ToT.Z = 0;
	D = VSize(ToT);
	AGL = BBHeliAGL();
	G = BBHeliGun();

	// Long range: aim a little high for the drop
	BBHeliAimLift = bBBHeliLongShot ? D * (bBBHeliRunRockets ? 0.006 : 0.004) : 0.0;
	AimLoc = BBHeliTargetLoc + vect(0,0,1) * BBHeliAimLift;
	BBHeliAimAt(AimLoc, AimYaw, AimPitch);

	if (bBBHeliLongShot)
	{
		// Move to the firing point on the line from the target to us, then sit there
		FirePoint = BBHeliTargetLoc - Normal(ToT) * BBHeliLongDist;
		if (VSize2D(FirePoint - BBHeli.Location) > 1500.0)
		{
			RunSpeed = FMin(1400.0, VSize2D(FirePoint - BBHeli.Location) * 0.4);
			BBNavVelocity(Normal(FirePoint - BBHeli.Location) * RunSpeed, FMax(AGL, (BBHeliMission == 'Scout') ? 1500.0 : 2500.0));
		}
		else
		{
			BBNavVelocity((FirePoint - BBHeli.Location) * 0.3, FMax(AGL, (BBHeliMission == 'Scout') ? 1500.0 : 2500.0));
		}
		MaxRange = (BBHeliMission == 'Scout') ? 11000.0 : 40000.0;
		TimeLimit = 25.0;
	}
	else
	{
		// Target well off the nose: slow down so the pedals can bring it round
		RunSpeed = (BBHeliMission == 'Scout') ? 1500.0 : BB_HeliRunSpeed;
		if (Abs(NormalizeRotAxis(AimYaw - BBHeli.Rotation.Yaw)) > 4500)	// 25 deg
		{
			RunSpeed = 500.0;
		}
		BBNavVelocity(Normal(ToT) * RunSpeed, FMax(AGL - 300.0, (BBHeliMission == 'Scout') ? 1200.0 : 1800.0));
		MaxRange = (BBHeliMission == 'Scout') ? 9000.0 : 30000.0;
		TimeLimit = 18.0;
	}
	bBBNavAim = true;

	if (BBHeliMission == 'Scout')
	{
		// Loach minigun
		BBHeliTryFire(AimLoc, 800.0, MaxRange, 0.99, 0, 1.2);
		bDone = G != none && BBHeliRunAmmoStart - G.AmmoCount >= 250;
	}
	else if (bBBHeliRunRockets)
	{
		BBHeliTryFire(AimLoc, 4000.0, MaxRange, bBBHeliLongShot ? 0.998 : 0.996, 0, 0.25);
		Fired = (G != none) ? (BBHeliRunAmmoStart - G.AmmoCount) : 0;
		bDone = Fired >= 4;
	}
	else
	{
		BBHeliTryFire(AimLoc, 2500.0, FMin(MaxRange, 25000.0), bBBHeliLongShot ? 0.996 : 0.993, 1, 1.2);
		bDone = G != none && BBHeliRunAltAmmoStart - G.AltAmmoCount >= 60;
	}

	if (bDone || AGL < 900.0 || BBHeliTaskTime() > TimeLimit ||
		(!bBBHeliLongShot && D < ((BBHeliMission == 'Scout') ? 1500.0 : 3500.0)) ||
		(bBBHeliLongShot && D < BBHeliLongDist * 0.5))
	{
		BBHeliStopFire();
		BBHeliAimLift = 0;
		BBHeliSetTask('Egress');
	}
}

function BBHeliThink()
{
	local float Dist, AGL, Waited;
	local int NumPass, NumHumans;
	local vector Away;

	AGL = BBHeliAGL();

	// Rotor or engine gone: get down now
	if (BBHeliEmergency() && BBHeliTask != 'Emergency' && BBHeliTask != 'Landed' && BBHeliTask != 'Done' && BBHeliTask != 'Bailout' &&
		!BBHeli.bVehicleOnGround && !BBHeli.bWasChassisTouchingGroundLastTick)
	{
		`log("[BetterBots][Heli]"@BBName()@"EMERGENCY (engine/rotor destroyed), landing where it can");
		BBHeliStopFire();
		BBHeliTellPassengers("[BetterBots] Emergencia: aterrizaje forzoso");
		BBHeliSetTask('Emergency');
	}

	// Low on ammo, damaged or wounded crew: back to base
	if (BBHeliIsCombatTask() && BBHeliTask != 'Transit' && BBHeliNeedsRearm())
	{
		`log("[BetterBots][Heli]"@BBName()@"returning to rearm/repair: ammoLow="$BBHeliAmmoLow()@"health="$BBHeli.Health@
			"engine="$BBHeli.bEngineDamaged@"rotor="$BBHeli.bMainRotorDamaged@"tail="$BBHeli.bTailRotorDamaged@"crewHurt="$BBHeliCrewHurt());
		BBHeliStopFire();
		BBHeliSetTask('RTB');
	}

	switch (BBHeliTask)
	{
		case 'Spool':
			BBNavGround();
			if (BBHeliHoldForHuman())
			{
				break;
			}
			if (BBHeliPadBusy() && BBHeliTaskTime() < 20.0)
			{
				break;
			}
			if (BBHeli.CurrentRPM >= BBHeli.NormalRPM * 0.95 || BBHeliTaskTime() > 25.0)
			{
				BBHeliHoldStart = 0;
				BBHeliSeatedSince = 0;
				BBHeliSetTask('Takeoff');
			}
			break;

		case 'Takeoff':
			BBNavHold(BBHeliHoldPoint, BB_HeliHoverAGL);
			if (AGL > BB_HeliHoverAGL * 0.85)
			{
				BBHeliStartMission();
			}
			else if (BBHeliTaskTime() > 40.0)
			{
				`log("[BetterBots][Heli] Takeoff timed out at AGL"@int(AGL));
				BBHeliLandHere();
			}
			break;

		case 'Hold':	// Test hover / Goto loiter
			BBNavHold(BBHeliHoldPoint, (BBHeliMission == 'Test') ? BB_HeliHoverAGL : BB_HeliLoiterAGL);
			if (BBHeliTaskTime() > BBHeliLoiterTime)
			{
				if (BBHeliMission == 'Test')
				{
					BBHeliLandHere();
				}
				else
				{
					BBHeliSetTask('RTB');
				}
			}
			break;

		case 'Transit':
			if (BBHeliMission == 'Lift')
			{
				BBHeliLiftTransit();
				break;
			}
			if (BBHeliMission == 'Scout' || BBHeliMission == 'Gunship')
			{
				BBHeliSetTask('Orbit');
				break;
			}
			Dist = BBNavRoute(BBHeliDest, BBHeliCruiseAGL(), BB_HeliCruiseSpeed);
			if (Dist < 700.0 && VSize2D(BBHeli.Velocity) < 400.0)
			{
				BBHeliHoldPoint = BBHeliDest;
				BBHeliSetTask('Hold');
				BBHeliHoldPoint = BBHeliDest;
			}
			break;

		case 'Standoff':	// Cobra
			BBHeliRefreshCenter();
			if (VSize2D(BBHeliCenter - BBHeliStandoffCenter) > 5000.0)
			{
				BBHeliPickStandoff();
			}
			if (BBHeliDist2D(BBHeliStandoff) > 3000.0)
			{
				BBNavRoute(BBHeliStandoff, BBHeliStandoffAGL, BB_HeliCruiseSpeed);
			}
			else
			{
				// Slow circle, never a static hover in the combat area
				BBNavOrbit(BBHeliStandoff, 1800.0, 1000.0, BBHeliStandoffAGL);
			}
			if (BBHeliTakeStrike())
			{
				break;
			}
			if (WorldInfo.TimeSeconds > BBHeliNextRun && (BBHeliHasAmmo(0) || BBHeliHasAmmo(1)) && BBHeliFindRunTarget(45000.0))
			{
				BBHeliStartRun();
			}
			break;

		case 'Orbit':	// Loach and Bushranger
			BBHeliRefreshCenter();
			if (WorldInfo.TimeSeconds > BBHeliNextVary)
			{
				BBHeliVaryOrbit();
			}
			if (BBHeliDist2D(BBHeliCenter) > BBHeliOrbitRadius + 6000.0)
			{
				BBNavRoute(BBHeliCenter, BBHeliCruiseAGL(), BB_HeliCruiseSpeed);
			}
			else
			{
				BBNavOrbit(BBHeliCenter, BBHeliOrbitRadius, 1300.0, BBHeliOrbitAGL);
			}
			if (BBHeliMission == 'Scout')
			{
				BBHeliSpot();
				if (WorldInfo.TimeSeconds > BBHeliNextRun && BBHeliHasAmmo(0) && BBHeliFindRunTarget(12000.0))
				{
					BBHeliStartRun();
				}
			}
			else if (BBHeliTakeStrike())
			{
				break;
			}
			else if (WorldInfo.TimeSeconds > BBHeliNextRun && BBHeliHasAmmo(0) && BBHeliFindRunTarget(30000.0) &&
				BBGetHM() != none && BBHM.BBIsAirThreat(BBHeliTarget))
			{
				BBHeliStartRun();
			}
			break;

		case 'RunIn':
			if (BBHeliMission == 'Scout')
			{
				BBHeliSpot();
			}
			BBHeliRunIn();
			break;

		case 'Egress':
			// Break off to the side and climb back out
			Away = BBHeli.Location - BBHeliTargetLoc;
			Away.Z = 0;
			Away = Normal(Away + (vect(0,0,1) cross Normal(Away)) * BBHeliOrbitDir);
			BBNavVelocity(Away * BB_HeliRunSpeed, (BBHeliMission == 'Attack') ? BBHeliStandoffAGL : BBHeliOrbitAGL + 800.0);
			if (BBHeliTaskTime() > ((BBHeliMission == 'Scout') ? 5.0 : 8.0))
			{
				BBHeliNextRun = WorldInfo.TimeSeconds + ((BBHeliMission == 'Scout') ? 10.0 : 6.0) + FRand() * 6.0;
				BBHeliSetTask(BBHeliResumeTask != '' ? BBHeliResumeTask : 'Orbit');
			}
			break;

		case 'Evade':
			// Zig-zag away and up
			if (FRand() < 0.15)
			{
				BBHeliEvadeVel = BBHeliEvadeVel + (vect(0,0,1) cross Normal(BBHeliEvadeVel)) * BBRandHeli(-900.0, 900.0);
				BBHeliEvadeVel = Normal(BBHeliEvadeVel) * 2400.0;
			}
			BBNavVelocity(BBHeliEvadeVel, FMax(AGL, BBHeliCruiseAGL()) + 1000.0);
			if (BBHeliMission == 'Scout')
			{
				BBHeliSpot();
			}
			if (WorldInfo.TimeSeconds > BBHeliEvadeUntil)
			{
				BBHeliNextRun = WorldInfo.TimeSeconds + 8.0;
				if (BBHeliMission == 'Attack')
				{
					BBHeliPickStandoff();
				}
				BBHeliSetTask(BBHeliResumeTask != '' ? BBHeliResumeTask : 'Orbit');
			}
			break;

		case 'RTB':
			Dist = BBNavRoute(BBHeliHome, BBHeliCruiseAGL(), BB_HeliCruiseSpeed);
			if (Dist < 2500.0)
			{
				BBHeliLandPoint = BBHeliHome;
				BBHeliSetTask('Approach');
			}
			break;

		case 'Approach':
			// Far: fly in slowing down. Last 30 m: hover across to the point (no overshooting circles)
			if (BBHeliDist2D(BBHeliLandPoint) > 1500.0)
			{
				BBNavMove(BBHeliLandPoint, BB_HeliApproachAGL, FMin(BB_HeliCruiseSpeed, FMax(BBHeliDist2D(BBHeliLandPoint) * 0.3, 300.0)));
			}
			else
			{
				BBNavHold(BBHeliLandPoint, BB_HeliApproachAGL);
			}
			// Taking too long (wind-milling around the spot): land where we are if it is flat
			if (BBHeliTaskTime() > 45.0 && BBGetHM() != none && BBHM.BBIsLandable(BBHeli.Location, BBHeliLandPoint, true))
			{
				`log("[BetterBots][Heli]"@BBName()@"approach took too long, landing here");
				BBHeliSetTask('Descend');
				break;
			}
			if (BBHeliMission == 'Lift' && BBHeliLiftAbortCheck())
			{
				break;
			}
			if (BBHeliDist2D(BBHeliLandPoint) < 300.0 && VSize2D(BBHeli.Velocity) < 250.0)
			{
				BBHeliSetTask('Descend');
			}
			break;

		case 'Descend':
			BBNavDescend(BBHeliLandPoint);
			if (BBHeliMission == 'Lift' && BBHeliLiftAbortCheck())
			{
				break;
			}
			if (BBHeli.bVehicleOnGround || BBHeli.bWasChassisTouchingGroundLastTick)
			{
				BBHeliTouchdownVZ = BBHeli.Velocity.Z;
				BBHeliSetTask('Landed');
			}
			break;

		case 'Emergency':
			// Engine out with a working rotor: glide down toward our base
			// (autorotation). Rotors gone: straight down where we are.
			if (!BBHeli.bMainRotorDestroyed && !BBHeli.bTailRotorDestroyed && AGL > 700.0 && BBHeliDist2D(BBHeliHome) > 3000.0)
			{
				BBNavVelocity(Normal(BBHeliHome - BBHeli.Location) * 1200.0, 100.0);
			}
			else
			{
				BBNavDescend(BBHeli.Location);
			}
			if (BBHeli.bVehicleOnGround || BBHeli.bWasChassisTouchingGroundLastTick)
			{
				BBHeliSetTask('Landed');
			}
			break;

		case 'Landed':
			BBNavGround();
			if (BBHeliTaskTime() > 1.5)
			{
				BBHeliOnLanded();
			}
			break;

		case 'Unload':	// Lift at the LZ
			BBNavGround();
			NumPass = (BBGetHM() != none) ? BBHM.NumPassengers(BBHeli, NumHumans) : 0;
			// Everyone off (humans get the same 8 s), then go
			if ((NumPass <= 0 && BBHeliTaskTime() > 2.0) || BBHeliTaskTime() > 8.0)
			{
				BBHeliLZ = vect(0,0,0);
				BBHeliSetTask('Spool');
			}
			break;

		case 'Wait':	// Lift at base: passengers board, repairs happen
			BBNavGround();
			BBHeliLiftWait();
			break;

		case 'Rearm':
			BBNavGround();
			Waited = BBHeliTaskTime();
			if (BBHeliEmergency() && Waited > 300.0)
			{
				// Not getting fixed here: abandon it
				BBHeliLeaveHeli(true);
				break;
			}
			if ((Waited > 5.0 && BBHeli.GetResupplyAndRepairTime() <= 0 && !BBHeliNeedsRearm()) || (Waited > 150.0 && !BBHeliEmergency()))
			{
				`log("[BetterBots][Heli]"@BBName()@"rearmed/repaired in"@int(Waited)$"s, health"@BBHeli.Health);
				BBHeliSetTask('Spool');
			}
			break;

		case 'Done':
			BBNavGround();
			// After a console test, back to the heli's normal job
			if (BBHeliTaskTime() > 10.0 && BBGetHM() != none && BBHM.HeliOnGround(BBHeli))
			{
				BBHeliMission = BBHM.HeliType(BBHeli);
				BBHeliSetTask((BBHeliMission == 'Lift') ? 'Wait' : 'Rearm');
			}
			break;
	}
}

/**
 * At base, before takeoff: a human who just got in gets a few seconds to
 * settle (or change their mind), and while a human is still picking a heli
 * at the base we stay on the ground (up to 2 min) so they can swap helis
 * and get a crew again.
 */
function bool BBHeliHoldForHuman()
{
	local bool bHold;

	if (BBGetHM() == none || VSize(BBHeli.Location - BBHM.HeliHome(BBHeli)) > 4000.0 || bBBHeliCede)
	{
		return false;
	}
	if (BBHM.BBHumanAboard(BBHeli))
	{
		if (BBHeliSeatedSince <= 0)
		{
			BBHeliSeatedSince = WorldInfo.TimeSeconds;
			if (BBHeliMission != 'Lift')
			{
				BBHeliTellPassengers("[BetterBots] Despegamos en 6 s");
			}
		}
		bHold = BBHeliMission != 'Lift' && WorldInfo.TimeSeconds - BBHeliSeatedSince < 6.0;
	}
	else
	{
		BBHeliSeatedSince = 0;
		bHold = BBHM.BBHumanAtHeliBase(BBHeli);
	}

	if (!bHold)
	{
		BBHeliHoldStart = 0;
		return false;
	}
	if (BBHeliHoldStart <= 0)
	{
		BBHeliHoldStart = WorldInfo.TimeSeconds;
		`log("[BetterBots][Heli]"@BBName()@"waits on the ground for the human at the heli base");
	}
	if (WorldInfo.TimeSeconds - BBHeliHoldStart > 30.0)
	{
		return false;
	}
	// Keep the spool-up timer from running out while we wait
	BBHeliTaskStart = WorldInfo.TimeSeconds;
	return true;
}

/** Enemy anti-air (SAM site) is up, or a missile is already coming */
/** Gunner that left with a human pilot and got no new heli: back to infantry */
function BBFreeIdleGunnerRole()
{
	if (Vehicle(Pawn) == none && BBCrewHeli == none && !bBBHeliPilot && !bBBHeliRider)
	{
		BBFreePilotRole();
	}
}

/**
 * Keeps clear of other helicopters (rotor strikes): pushes DesiredVel away
 * from any within 60 m and returns extra height for one of each pair.
 */
function float BBHeliSeparate(out vector DesiredVel)
{
	local ROVehicleHelicopter O;
	local vector Off;
	local float D, D2, Lift;

	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', O)
	{
		// Parked helis don't count (we land next to them at base)
		if (O == BBHeli || O.Health <= 0 || O.bDeleteMe || O.bVehicleOnGround || O.bWasChassisTouchingGroundLastTick)
		{
			continue;
		}
		Off = BBHeli.Location - O.Location;
		D = VSize(Off);
		if (D > 2200.0)
		{
			continue;
		}
		Off.Z = 0;
		D2 = VSize(Off);
		if (D2 < 50.0)
		{
			Off = vect(0,1,0) * ((string(BBHeli.Name) > string(O.Name)) ? 1.0 : -1.0);
		}
		DesiredVel += Normal(Off) * FMin((2200.0 - D) * 0.8, 1000.0) * ((BBHeliTask == 'Approach' || BBHeliTask == 'Descend') ? 0.3 : 1.0);
		// One of the two climbs over the other
		if (D2 < 2500.0 && string(BBHeli.Name) > string(O.Name))
		{
			Lift = FMax(Lift, 900.0);
		}
	}
	return Lift;
}

/** Another heli close by is taking off or landing: wait so the rotors don't meet */
function bool BBHeliPadBusy()
{
	local ROVehicleHelicopter O;

	foreach WorldInfo.AllPawns(class'ROVehicleHelicopter', O)
	{
		if (O != BBHeli && O.Health > 0 && VSize2D(O.Location - BBHeli.Location) < 3000.0 &&
			!(O.bVehicleOnGround || O.bWasChassisTouchingGroundLastTick) && O.Altitude < 2500)
		{
			return true;
		}
	}
	return false;
}

function bool BBHeliAAThreat()
{
	local ROTeamInfo ROTI;

	if (BBHeli == none)
	{
		return false;
	}
	if (BBHeli.bIncomingMissile)
	{
		return true;
	}
	if (WorldInfo.GRI == none || GetTeamNum() > 1)
	{
		return false;
	}
	ROTI = ROTeamInfo(WorldInfo.GRI.Teams[1 - GetTeamNum()]);
	return ROTI != none && ROTI.bAntiAirActive;
}

function float BBRandHeli(float A, float B)
{
	return A + FRand() * (B - A);
}

function BBHeliLandHere()
{
	BBHeliLandPoint = BBHeli.Location;
	BBHeliSetTask('Descend');
}

function BBHeliOnLanded()
{
	if (BBHeliTask == 'Landed' && BBHeliMaxAGL > 0)
	{
		`log("[BetterBots][Heli]"@BBName()@"LANDED. Flight"@int(WorldInfo.TimeSeconds - BBHeliFlightStart)$"s, max AGL"@int(BBHeliMaxAGL)@
			"touchdown VZ ~"$int(BBHeliTouchdownVZ)@"from home"@int(BBHeliDist2D(BBHeliHome))@"health"@BBHeli.Health);
		BBHeliMaxAGL = 0;
	}

	// Rotor/engine gone away from base: crew gets out (at base it gets repaired)
	if (BBHeliEmergency() && !BBHeliNearHome())
	{
		BBHeliTellPassengers("[BetterBots] Fuera del helicoptero");
		BBHeliSetTask('Bailout');
		SetTimer(3.0, false, 'BBHeliBailoutTimer');
		return;
	}

	if (BBHeliNearHome())
	{
		if (bBBHeliCede)
		{
			bBBHeliCede = false;
			BBHeliLeaveHeli(true);
			if (BBGetHM() != none)
			{
				BBHM.BBCedeDone(BBAIController(self));
			}
			return;
		}
		switch (BBHeliMission)
		{
			case 'Test':
			case 'Goto':
			case 'Home':
				BBHeliSetTask('Done');
				return;
			case 'Lift':
				BBHeliSetTask('Wait');
				return;
		}
		BBHeliSetTask('Rearm');
		return;
	}

	if (BBHeliMission == 'Lift' && BBHeliLZ != vect(0,0,0) && BBHeliDist2D(BBHeliLZ) < 1500.0)
	{
		BBHeliTellPassengers("[BetterBots] En la zona de aterrizaje, todos fuera");
		BBHeliSetTask('Unload');
		return;
	}
	if (BBHeliMission == 'Test')
	{
		BBHeliSetTask('Done');
		return;
	}
	BBHeliSetTask('Spool');
}

function BBHeliBailoutTimer()
{
	if (BBIsFlyingHeli() && BBHeliTask == 'Bailout')
	{
		BBHeliLeaveHeli(true);
	}
}

/*-----------------------------------------------------------------------------
	Transport (Lift)
-----------------------------------------------------------------------------*/

function BBHeliLiftWait()
{
	local int NumPass, NumHumans;
	local float Waited;
	local bool bGo;

	if (BBGetHM() == none)
	{
		return;
	}
	NumPass = BBHM.NumPassengers(BBHeli, NumHumans);
	Waited = BBHeliTaskTime();

	if (NumHumans > 0)
	{
		if (BBHeliHumanAboardSince <= 0)
		{
			BBHeliHumanAboardSince = WorldInfo.TimeSeconds;
			BBHeliTellPassengers("[BetterBots] El Huey sale en 10 s");
		}
	}
	else
	{
		BBHeliHumanAboardSince = 0;
	}

	// Still being repaired: wait (up to 90 s, always for a destroyed rotor/engine)
	if ((BBHeli.GetResupplyAndRepairTime() > 0 && Waited < 90.0) || BBHeliEmergency())
	{
		return;
	}

	if (NumHumans > 0 && WorldInfo.TimeSeconds - BBHeliHumanAboardSince >= 10.0)
	{
		bGo = true;
	}
	else if (NumPass >= 3)
	{
		bGo = true;
	}
	else if (NumPass >= 1 && Waited >= 60.0)
	{
		bGo = true;
	}
	else if (Waited >= 180.0)
	{
		// Nobody came: fly the run anyway (door gunners still help)
		bGo = true;
	}
	if (!bGo)
	{
		return;
	}

	if (WorldInfo.TimeSeconds < BBHeliNextLZTry)
	{
		return;
	}
	BBHeliLZExtra = 0;
	if (!BBHM.BBPickLZ(BBHeli, BBHeliLZExtra, BBHeliLZ))
	{
		// No landing zone found: try again in a while
		BBHeliLZ = vect(0,0,0);
		BBHeliNextLZTry = WorldInfo.TimeSeconds + 5.0;
		return;
	}
	`log("[BetterBots][Heli]"@BBName()@"lifting"@NumPass@"passengers ("$NumHumans@"human) to LZ"@BBHeliLZ@
		"dist"@int(BBHeliDist2D(BBHeliLZ)));
	BBHeliTellPassengers("[BetterBots] Despegamos hacia la zona de aterrizaje");
	BBHeliHumanAboardSince = 0;
	BBHeliSetTask('Spool');
}

function BBHeliLiftTransit()
{
	local float Dist;

	if (!BBHeliCarriesPassengers())
	{
		BBHeliSetTask('RTB');
		return;
	}
	Dist = BBNavRoute(BBHeliLZ, BBHeliCruiseAGL(), BB_HeliCruiseSpeed);
	if (BBHeliLiftAbortCheck())
	{
		return;
	}
	if (Dist < 3000.0)
	{
		BBHeliLandPoint = BBHeliLZ;
		BBHeliSetTask('Approach');
	}
}

/** Taking fire near the LZ: pick another one further back (or go home if badly hit) */
function bool BBHeliLiftAbortCheck()
{
	local vector NewLZ;

	if (BBHeliLegDamage < 15.0 || BBHeliDist2D(BBHeliLZ) > 9000.0 || BBHeliLZ == vect(0,0,0))
	{
		return false;
	}
	if (BBGetHM() != none)
	{
		BBHM.BBAddThreat(GetTeamNum(), BBHeliLZ, 40.0);
	}
	if (BBHeli.Health < BBHeli.HealthMax * 0.5 || BBHeliEmergency())
	{
		`log("[BetterBots][Heli]"@BBName()@"LZ too hot and badly damaged, back to base with the passengers");
		BBHeliTellPassengers("[BetterBots] Zona de aterrizaje bajo fuego, volvemos a base");
		BBHeliLZ = vect(0,0,0);
		BBHeliSetTask('RTB');
		return true;
	}
	BBHeliLZExtra += 4000.0;
	if (BBGetHM() != none && BBHM.BBPickLZ(BBHeli, BBHeliLZExtra, NewLZ))
	{
		`log("[BetterBots][Heli]"@BBName()@"LZ under fire, new LZ further back"@NewLZ);
		BBHeliTellPassengers("[BetterBots] Fuego en la zona de aterrizaje, buscamos otra");
		BBHeliLZ = NewLZ;
		BBHeliSetTask('Transit');
	}
	else
	{
		BBHeliLZ = vect(0,0,0);
		BBHeliSetTask('RTB');
	}
	return true;
}

/*-----------------------------------------------------------------------------
	Pilot state
-----------------------------------------------------------------------------*/

function BBHeliResumeFly()
{
	if (BBIsFlyingHeli() && !IsInState('BBHeliFly'))
	{
		GotoState('BBHeliFly');
	}
	else
	{
		bBBHeliResume = false;
	}
}

function BBRideResume()
{
	if (bBBHeliRider && ROWeaponPawn(Pawn) != none && !IsInState('BBHeliRide'))
	{
		GotoState('BBHeliRide');
	}
}

function BBHeliControl(float DeltaTime)
{
	if (!BBIsFlyingHeli())
	{
		`log("[BetterBots][Heli]"@BBName()@"lost the helicopter (destroyed or left), task"@BBHeliTask);
		bBBHeliPilot = false;
		bBBHeliFiring = false;
		GotoState('FindNextState');
		return;
	}

	BBHeliMonitorDamage(DeltaTime);
	if (WorldInfo.TimeSeconds >= BBHeliNextThink)
	{
		BBHeliNextThink = WorldInfo.TimeSeconds + 0.25;
		BBHeliThink();
		if (!BBIsFlyingHeli())
		{
			return;	// Landed and got out
		}
	}
	if (BBHeliTask == 'RunIn')
	{
		// Keep the aim point fresh every tick
		if (BBHeliTarget != none && BBHeliTarget.Health > 0)
		{
			BBHeliTargetLoc = BBHeliTarget.Location + vect(0,0,20);
		}
	}
	BBHeliFireTick();
	BBHeliSteer(DeltaTime);
}

state BBHeliFly
{
	ignores SeePlayer, HearNoise, EnemyNotVisible, NotifyTakeHit, NotifyObjectivesUpdated;

	function EvaluateObjectives() {}

	event BeginState(Name PreviousStateName)
	{
		if (bBBHeliResume)
		{
			bBBHeliResume = false;
			`log("[BetterBots][Heli]"@BBName()@"back in the autopilot after state"@PreviousStateName);
			return;
		}
		BBHeliTaskStart = WorldInfo.TimeSeconds;
		BBHeliFlightStart = WorldInfo.TimeSeconds;
		BBHeliCollectiveTrim = 0.75;
		BBNavYaw = BBHeli.Rotation.Yaw;
		BBHeliTargetYaw = BBHeli.Rotation.Yaw;
		BBHeliLastYaw = BBHeli.Rotation.Yaw;
		BBHeliHoldPoint = BBHeli.Location;
		BBHeliMaxAGL = 0;
		BBHeliNextLog = 0;
		BBHeliNextTerrain = 0;
		BBHeliObstacleUntil = 0;
		BBHeliNextThink = 0;
		BBHeliLastHealth = BBHeli.Health;
		BBHeliRecentDamage = 0;
		BBHeliNextRun = WorldInfo.TimeSeconds + 5.0;
		BBHeliOrbitDir = 1.0;
		bBBHeliFiring = false;
		BBHeliHumanAboardSince = 0;
		BBNavGround();

		// Land back on the pad it came from
		if (BBGetHM() != none && BBHeli.ParentFactory != none && VSize2D(BBHeli.Location - BBHeli.ParentFactory.Location) < 3000.0)
		{
			BBHeliHome = BBHeli.ParentFactory.Location;
		}
		else
		{
			BBHeliHome = BBHeli.Location;
		}

		BBHeliTask = '';
		if (BBHeliMission == 'Lift' && BBHeliNearHome())
		{
			BBHeliSetTask('Wait');
		}
		else
		{
			BBHeliSetTask('Spool');
		}
		`log("[BetterBots][Heli]"@BBName()@"autopilot engaged in"@class'BBHeliManager'.static.HeliName(BBHeli)@"mission"@BBHeliMission@"home"@BBHeliHome);
	}

	event EndState(Name NextStateName)
	{
		BBHeliStopFire();
		// Some stock event switched state while we are flying: come straight back
		if (BBIsFlyingHeli())
		{
			`log("[BetterBots][Heli]"@BBName()@"state changed to"@NextStateName@"while flying, resuming");
			bBBHeliResume = true;
			SetTimer(0.01, false, 'BBHeliResumeFly');
		}
	}

	event Tick(float DeltaTime)
	{
		global.Tick(DeltaTime);
		BBHeliControl(DeltaTime);
	}
}

/*-----------------------------------------------------------------------------
	Riders: passengers, door gunners, turret gunners
-----------------------------------------------------------------------------*/

function BBGunStop()
{
	if (bBBGunFiring && BBRideHeli != none)
	{
		BBRideHeli.AIEndFireWeapon(BBRideSeat, BBGunMode);
	}
	bBBGunFiring = false;
}

function byte BBGunPickMode(ROVehicleWeapon G)
{
	// Cobra turret: minigun on the alt mode, grenade launcher on the primary
	if (ROHWeap_AH1G_Turret(G) != none && G.MaxAltAmmoCount > 0 && G.AltAmmoCount > 0)
	{
		return 1;
	}
	return 0;
}

function BBGunTick(ROVehicleHelicopter H, int Seat)
{
	local ROVehicleWeapon G;
	local vector GunLoc, Aim;
	local rotator GunRot;
	local float D, Range;
	local bool bAligned, bHasAmmo;

	G = H.Seats[Seat].Gun;
	if (G == none || BBGetHM() == none)
	{
		return;
	}
	Range = class'BBHeliManager'.static.IsGunnerCopilotSeat(H, Seat) ? 15000.0 : 10000.0;
	G.GetFireStartLocationAndRotation(GunLoc, GunRot);

	if (WorldInfo.TimeSeconds > BBGunNextPick || BBGunTarget == none || BBGunTarget.Health <= 0)
	{
		BBGunTarget = BBHM.BBPickAirTarget(H, H.Location, Range, Range);
		BBGunNextPick = WorldInfo.TimeSeconds + 1.0 + FRand();
		BBGunAimStart = WorldInfo.TimeSeconds;
	}
	if (BBGunTarget == none || !FastTrace(BBGunTarget.Location + vect(0,0,40), GunLoc))
	{
		BBGunStop();
		return;
	}

	D = VSize(BBGunTarget.Location - GunLoc);
	// Lead the target and allow for our own speed
	Aim = BBGunTarget.Location + vect(0,0,35) + (BBGunTarget.Velocity - H.Velocity) * (D / 30000.0);
	Focus = BBGunTarget;
	bAligned = H.OrientSeatWeapon(Seat, Normal(Aim - GunLoc), 1100);
	if (!bAligned && WorldInfo.TimeSeconds - BBGunAimStart > 2.5)
	{
		// Out of this gun's arc: look for something else
		BBGunStop();
		BBGunNextPick = 0;
		return;
	}

	BBGunMode = bBBGunFiring ? BBGunMode : BBGunPickMode(G);
	bHasAmmo = (BBGunMode == 0) ? G.AmmoCount > 0 : G.AltAmmoCount > 0;
	if (bAligned && bHasAmmo && !bBBGunFiring && WorldInfo.TimeSeconds >= BBGunNextBurst &&
		!BBHM.BBFriendliesNear(GetTeamNum(), BBGunTarget.Location, 2500.0))
	{
		if (H.AIFireWeapon(Seat, Aim, BBGunMode))
		{
			bBBGunFiring = true;
			BBGunBurstEnd = WorldInfo.TimeSeconds + 1.0 + FRand() * 1.5;
		}
	}
	else if (bBBGunFiring)
	{
		H.currAimPt = Aim;
	}
	if (bBBGunFiring && (WorldInfo.TimeSeconds > BBGunBurstEnd || !bAligned || !bHasAmmo))
	{
		BBGunStop();
		BBGunNextBurst = WorldInfo.TimeSeconds + 0.6 + FRand();
	}
}

function BBRideTick()
{
	local ROVehicleHelicopter H;

	H = BBRideHeli;
	if (H == none || H.Health <= 0 || ROWeaponPawn(Pawn) == none || BBGetHM() == none)
	{
		ClearTimer('BBRideTick');
		return;
	}

	if (!bBBHeliGunner)
	{
		// Passenger: off at the LZ (or when a human pilot lands near the fight)
		if (BBHM.BBShouldUnload(H))
		{
			`log("[BetterBots][Heli]"@BBName()@"unloading from the"@BBHM.HeliName(H));
			BBLeaveVehicle();
			return;
		}
		// Sitting at base for too long (human pilot not going anywhere)
		if (WorldInfo.TimeSeconds - BBRideStart > 120.0 && BBHM.HeliOnGround(H) && VSize(H.Location - BBHM.HeliHome(H)) < 4000.0)
		{
			BBLeaveVehicle();
		}
		return;
	}

	// Gunner: stays with the heli. Gets out if nobody is flying it any more
	if (H.Controller == none && BBHM.HeliOnGround(H))
	{
		// The human pilot jumped out (maybe swapping helis): get out quickly and
		// keep the gunner role a while so the manager can put us in their new heli
		if (bBBRideHumanPilot && BBGetHM() != none && BBHM.BBHumanAtHeliBase(H) && BBRideStart < WorldInfo.TimeSeconds - 3.0)
		{
			`log("[BetterBots][Heli]"@BBName()@"pilot left, gets out and waits for a new heli");
			BBLeaveVehicle();
			SetTimer(60.0, false, 'BBFreeIdleGunnerRole');
		}
		else if (BBRideStart < WorldInfo.TimeSeconds - 60.0)
		{
			// Waited a minute for a pilot
			BBLeaveVehicle();
			BBFreePilotRole();
		}
		return;
	}
	bBBRideHumanPilot = PlayerController(H.Controller) != none;
	BBRideStart = WorldInfo.TimeSeconds;
	BBGunTick(H, BBRideSeat);
}

state BBHeliRide
{
	ignores SeePlayer, HearNoise, EnemyNotVisible, NotifyTakeHit, NotifyObjectivesUpdated;

	function EvaluateObjectives() {}

	event BeginState(Name PreviousStateName)
	{
		BBRideHeli = BBCurrentHeli();
		BBRideSeat = (ROWeaponPawn(Pawn) != none) ? ROWeaponPawn(Pawn).MySeatIndex : -1;
		BBRideStart = WorldInfo.TimeSeconds;
		bBBRideHumanPilot = false;
		bBBGunFiring = false;
		BBGunTarget = none;
		SetTimer(0.25, true, 'BBRideTick');
	}

	event EndState(Name NextStateName)
	{
		ClearTimer('BBRideTick');
		BBGunStop();
		if (bBBHeliRider && ROWeaponPawn(Pawn) != none)
		{
			SetTimer(0.01, false, 'BBRideResume');
		}
	}
}

defaultproperties
{
	BBCrewSeat=-1
	BBHeliOrbitDir=1.0
}
